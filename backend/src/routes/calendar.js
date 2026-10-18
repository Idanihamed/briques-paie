import { Router } from 'express';
import { z } from 'zod';
import { ah, badRequest, conflict, notFound } from '../lib/errors.js';
import { logAudit } from '../lib/audit.js';
import { assertDate, assertMonth, frDate, monthBounds, todayStr } from '../lib/dates.js';
import { requireTeamAccess, teamsOf } from '../services/access.js';
import { KIND_LABELS, dateRange, loadCalendar, loadRestWeekdays, resolveDay, weekdayOf } from '../services/calendar.js';
import { loadEntries } from '../services/payroll.js';

const uuid = z.string().uuid();
const MAX_RANGE_DAYS = 93;

const rangeSchema = z.object({
  from: z.string(),
  to: z.string().optional(),
  teamId: uuid.nullable().optional(), // null / absent = toutes les équipes
});

function datesOf(b) {
  assertDate(b.from, 'date de début');
  const to = b.to ?? b.from;
  assertDate(to, 'date de fin');
  if (to < b.from) throw badRequest('La date de fin précède la date de début.');
  const dates = dateRange(b.from, to);
  if (dates.length > MAX_RANGE_DAYS) throw badRequest(`Période trop longue (${MAX_RANGE_DAYS} jours maximum).`);
  return dates;
}

/**
 * Calendrier de travail : quels jours sont travaillés, pour quelle équipe, et où en est la saisie.
 * Lecture : admin (toutes les équipes) et superviseurs (leurs équipes). Écriture : admin.
 */
export function calendarRouter({ db, auth, admin }) {
  const r = Router();
  r.use(auth);

  // Vue d'un mois : un état par équipe et par jour (aucun montant).
  r.get('/', ah(async (req, res) => {
    const { month, teamId } = z.object({ month: z.string(), teamId: uuid.optional() }).parse(req.query);
    assertMonth(month);

    let teams;
    if (teamId) {
      const t = await requireTeamAccess(db, req.user, teamId);
      teams = [{ id: t.id, name: t.name }];
    } else {
      teams = (await teamsOf(db, req.user)).map((t) => ({ id: t.id, name: t.name }));
    }

    const { start, endExclusive, days } = monthBounds(month);
    const cal = await loadCalendar(db, start, endExclusive);
    const entries = await loadEntries(db, start, endExclusive);
    const byKey = new Map(entries.map((e) => [`${e.teamId}|${e.date}`, e]));
    const today = todayStr();

    const stateOf = (info, entry, date) => {
      if (!info.working) return 'off';
      if (entry) return !Object.values(entry.presence).includes('unset') && entry.bricks != null ? 'complete' : 'incomplete';
      if (date > today) return 'future';
      return date === today ? 'pending' : 'missing';
    };

    const out = [];
    for (let d = 1; d <= days; d++) {
      const date = `${month}-${String(d).padStart(2, '0')}`;
      out.push({
        date,
        weekday: weekdayOf(date),
        teams: teams.map((t) => {
          const info = resolveDay(cal, date, t.id);
          const entry = byKey.get(`${t.id}|${date}`);
          return {
            teamId: t.id,
            working: info.working,
            kind: info.kind,
            reason: info.reason,
            source: info.source,
            state: stateOf(info, entry, date),
            bricks: entry?.bricks ?? null,
          };
        }),
      });
    }
    res.json({ month, today, restWeekdays: cal.restWeekdays, teams, days: out });
  }));

  // Jours de repos hebdomadaires (0 = dimanche … 6 = samedi).
  r.put('/settings', admin, ah(async (req, res) => {
    const { restWeekdays } = z.object({
      restWeekdays: z.array(z.number().int().min(0).max(6)).max(6, 'Au moins un jour doit rester travaillé.'),
    }).parse(req.body);
    const list = [...new Set(restWeekdays)].sort();
    await db.tx(async (q) => {
      const old = await loadRestWeekdays(q);
      await q.query(
        `insert into app_settings (key, value, updated_by) values ('rest_weekdays', $1::jsonb, $2)
         on conflict (key) do update set value = excluded.value, updated_at = now(), updated_by = excluded.updated_by`,
        [JSON.stringify(list), req.user.id],
      );
      await logAudit(q, req.user, {
        action: 'Calendrier : repos hebdomadaire',
        object: 'Jours de repos',
        oldValue: JSON.stringify(old),
        newValue: JSON.stringify(list),
      });
    });
    res.json({ restWeekdays: list });
  }));

  // Déclare une période : non travaillée (repos, férié, intempérie, panne, autre) ou travaillée à titre exceptionnel.
  r.post('/days', admin, ah(async (req, res) => {
    const b = rangeSchema.extend({
      kind: z.enum(['work', 'rest', 'holiday', 'weather', 'breakdown', 'other']),
      reason: z.string().trim().max(200).nullable().optional(),
    }).parse(req.body);
    const dates = datesOf(b);
    const teamId = b.teamId ?? null;

    await db.tx(async (q) => {
      let teamName = 'Toutes les équipes';
      if (teamId) {
        const t = (await q.query('select name from teams where id = $1', [teamId])).rows[0];
        if (!t) throw notFound('Équipe introuvable.');
        teamName = t.name;
      }
      // On ne déclare pas « non travaillé » un jour déjà saisi : l'historique reste cohérent.
      if (b.kind !== 'work') {
        const used = (await q.query(
          `select e.work_date, t.name from day_entries e join teams t on t.id = e.team_id
            where e.work_date = any($1::date[]) and ($2::uuid is null or e.team_id = $2)
            order by e.work_date limit 5`,
          [dates, teamId],
        )).rows;
        if (used.length) {
          throw conflict(
            `Une saisie existe déjà : ${used.map((u) => `${frDate(u.work_date)} (${u.name})`).join(', ')}. `
              + 'Ces jours ne peuvent pas être déclarés non travaillés.',
            'entries_exist',
          );
        }
      }
      await q.query(
        `delete from calendar_days where work_date = any($1::date[])
            and coalesce(team_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce($2::uuid, '00000000-0000-0000-0000-000000000000'::uuid)`,
        [dates, teamId],
      );
      for (const date of dates) {
        await q.query(
          'insert into calendar_days (work_date, team_id, kind, reason, created_by) values ($1, $2, $3, $4, $5)',
          [date, teamId, b.kind, b.reason ?? null, req.user.id],
        );
      }
      await logAudit(q, req.user, {
        action: 'Calendrier : jours modifiés',
        object: teamName,
        newValue: `${KIND_LABELS[b.kind]} · ${frDate(dates[0])}${dates.length > 1 ? ` → ${frDate(dates.at(-1))} (${dates.length} jours)` : ''}`,
        reason: b.reason ?? null,
      });
    });
    res.status(201).json({ ok: true, days: dates.length });
  }));

  // Rétablit le calendrier habituel (supprime les exceptions de la période).
  r.post('/days/clear', admin, ah(async (req, res) => {
    const b = rangeSchema.parse(req.body);
    const dates = datesOf(b);
    const teamId = b.teamId ?? null;
    await db.tx(async (q) => {
      const done = await q.query(
        `delete from calendar_days where work_date = any($1::date[])
            and coalesce(team_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce($2::uuid, '00000000-0000-0000-0000-000000000000'::uuid)
         returning work_date`,
        [dates, teamId],
      );
      await logAudit(q, req.user, {
        action: 'Calendrier : jours rétablis',
        object: teamId ? (await q.query('select name from teams where id = $1', [teamId])).rows[0]?.name ?? 'Équipe' : 'Toutes les équipes',
        newValue: `${frDate(dates[0])}${dates.length > 1 ? ` → ${frDate(dates.at(-1))}` : ''} · ${done.rows.length} exception(s) retirée(s)`,
      });
    });
    res.json({ ok: true });
  }));

  return r;
}
