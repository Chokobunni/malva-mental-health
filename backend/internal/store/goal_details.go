package store

import (
	"errors"
	"sort"
	"strings"
	"time"
	"unicode/utf8"

	"malva/backend/internal/clock"
)

// GoalDetails is the persisted, optional configuration for a patient's habit.
// A nil configuration retains the legacy yes/no behavior and weekly target.
type GoalDetails struct {
	Note       string     `json:"note"`
	Method     string     `json:"method"`
	Target     int        `json:"target"`
	Unit       string     `json:"unit"`
	Steps      []GoalStep `json:"steps"`
	StartDate  string     `json:"start_date"`
	Time       string     `json:"time"`
	Recurrence string     `json:"recurrence"`
	Interval   int        `json:"interval"`
	Weekdays   []int      `json:"weekdays"`
	Reminders  []int      `json:"reminders"`
	AutoFail   bool       `json:"auto_fail"`
	LockPast   bool       `json:"lock_past"`
}

type GoalStep struct {
	ID    string `json:"id"`
	Label string `json:"label"`
}

// Pointers distinguish an omitted field from an intentional zero/empty update.
type HabitProgressPatch struct {
	Value            *int
	CompletedStepIDs *[]string
}

func ValidateGoalDetails(d *GoalDetails) error {
	if d == nil {
		return nil
	}
	if d.Method != "yes_no" && d.Method != "numeric" && d.Method != "checklist" {
		return errors.New("method harus yes_no, numeric, atau checklist")
	}
	if d.Target < 0 || d.Target > 1000000 || (d.Method == "numeric" && d.Target < 1) {
		return errors.New("target numeric harus 1–1000000")
	}
	if utf8.RuneCountInString(d.Note) > 5000 || utf8.RuneCountInString(d.Unit) > 80 {
		return errors.New("note maksimal 5000 dan unit maksimal 80 karakter")
	}
	if _, err := goalDate(d.StartDate); err != nil {
		return errors.New("start_date wajib YYYY-MM-DD")
	}
	if d.Time != "" {
		parsed, err := time.ParseInLocation("15:04", d.Time, clock.Location())
		if err != nil || parsed.Format("15:04") != d.Time {
			return errors.New("time harus HH:mm atau kosong")
		}
	}
	maxInterval := 365
	if d.Recurrence == "weekly" {
		maxInterval = 52
	} else if d.Recurrence != "daily" {
		return errors.New("recurrence harus daily atau weekly")
	}
	if d.Interval < 1 || d.Interval > maxInterval {
		return errors.New("interval di luar batas recurrence")
	}
	if d.Recurrence == "weekly" && len(d.Weekdays) == 0 {
		return errors.New("weekdays wajib untuk recurrence weekly")
	}
	days := map[int]bool{}
	for _, day := range d.Weekdays {
		if day < 1 || day > 7 || days[day] {
			return errors.New("weekdays harus unik dalam 1–7")
		}
		days[day] = true
	}
	if len(d.Steps) > 100 || (d.Method == "checklist" && len(d.Steps) == 0) {
		return errors.New("checklist memerlukan 1–100 langkah")
	}
	ids := map[string]bool{}
	for _, step := range d.Steps {
		if strings.TrimSpace(step.ID) == "" || utf8.RuneCountInString(step.ID) > 64 || ids[step.ID] {
			return errors.New("id langkah wajib unik dan maksimal 64 karakter")
		}
		if strings.TrimSpace(step.Label) == "" || utf8.RuneCountInString(step.Label) > 500 {
			return errors.New("label langkah wajib diisi dan maksimal 500 karakter")
		}
		ids[step.ID] = true
	}
	if len(d.Reminders) > 10 {
		return errors.New("maksimal 10 pengingat")
	}
	offsets := map[int]bool{}
	for _, offset := range d.Reminders {
		if offset < 0 || offset > 10080 || offsets[offset] {
			return errors.New("reminders harus unik dalam 0–10080 menit")
		}
		offsets[offset] = true
	}
	return nil
}

func goalDate(s string) (time.Time, error) {
	d, err := time.ParseInLocation("2006-01-02", s, clock.Location())
	if err != nil || d.Format("2006-01-02") != s || d.Year() < 1 {
		return time.Time{}, errors.New("tanggal harus YYYY-MM-DD")
	}
	return d, nil
}

func goalDay(t time.Time) time.Time {
	t = t.In(clock.Location())
	return time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, clock.Location())
}

func goalDayDistance(from, to time.Time) int {
	return int((goalDay(to).Unix() - goalDay(from).Unix()) / 86400)
}

func goalISOWeekday(t time.Time) int {
	day := int(t.Weekday())
	if day == 0 {
		return 7
	}
	return day
}

func goalDue(d *GoalDetails, on time.Time) bool {
	if d == nil {
		return true
	}
	start, err := goalDate(d.StartDate)
	if err != nil || d.Interval < 1 {
		return false
	}
	days := goalDayDistance(start, on)
	if days < 0 {
		return false
	}
	if d.Recurrence == "daily" {
		return days%d.Interval == 0
	}
	if d.Recurrence != "weekly" {
		return false
	}
	monday := start.AddDate(0, 0, 1-goalISOWeekday(start))
	if (goalDayDistance(monday, on)/7)%d.Interval != 0 {
		return false
	}
	for _, day := range d.Weekdays {
		if day == goalISOWeekday(on) {
			return true
		}
	}
	return false
}

// previousGoalDue jumps across inactive interval weeks instead of scanning days.
func previousGoalDue(d *GoalDetails, on time.Time) (time.Time, bool) {
	on = goalDay(on)
	if d == nil {
		return on, true
	}
	start, err := goalDate(d.StartDate)
	if err != nil || on.Before(start) || d.Interval < 1 {
		return time.Time{}, false
	}
	if d.Recurrence == "daily" {
		return on.AddDate(0, 0, -(goalDayDistance(start, on) % d.Interval)), true
	}
	if d.Recurrence != "weekly" || len(d.Weekdays) == 0 {
		return time.Time{}, false
	}
	anchor := start.AddDate(0, 0, 1-goalISOWeekday(start))
	week := goalDayDistance(anchor, on) / 7
	activeWeek := week - week%d.Interval
	for activeWeek >= 0 {
		monday := anchor.AddDate(0, 0, 7*activeWeek)
		for day := 7; day >= 1; day-- {
			candidate := monday.AddDate(0, 0, day-1)
			if !candidate.After(on) && !candidate.Before(start) && goalDue(d, candidate) {
				return candidate, true
			}
		}
		activeWeek -= d.Interval
	}
	return time.Time{}, false
}

func validateHabitDate(d *GoalDetails, on, now time.Time) error {
	if d == nil {
		return nil
	}
	today := goalDay(now)
	if on.After(today) {
		return errors.New("habit tidak dapat dicatat untuk tanggal mendatang")
	}
	if !goalDue(d, on) {
		return errors.New("habit tidak dijadwalkan pada tanggal ini")
	}
	if d.LockPast && on.Before(today.AddDate(0, 0, -1)) {
		return errors.New("tanggal habit sudah dikunci")
	}
	return nil
}

func applyHabitProgress(d *GoalDetails, current HabitLog, done bool, p HabitProgressPatch) (HabitLog, error) {
	if p.Value != nil {
		if *p.Value < 0 || *p.Value > 1000000 {
			return HabitLog{}, errors.New("value harus 0–1000000")
		}
		current.Value = *p.Value
	}
	if p.CompletedStepIDs != nil {
		allowed := map[string]bool{}
		if d != nil {
			for _, step := range d.Steps {
				allowed[step.ID] = true
			}
		}
		seen := map[string]bool{}
		for _, id := range *p.CompletedStepIDs {
			if !allowed[id] || seen[id] {
				return HabitLog{}, errors.New("completed_step_ids harus unik dan terdaftar pada goal")
			}
			seen[id] = true
		}
		current.CompletedStepIDs = append([]string{}, (*p.CompletedStepIDs)...)
	}
	if current.CompletedStepIDs == nil {
		current.CompletedStepIDs = []string{}
	}
	current.Done = done
	if d != nil {
		switch d.Method {
		case "numeric":
			current.Done = current.Value >= d.Target
		case "checklist":
			completed := map[string]bool{}
			for _, id := range current.CompletedStepIDs {
				completed[id] = true
			}
			current.Done = len(d.Steps) > 0
			for _, step := range d.Steps {
				if !completed[step.ID] {
					current.Done = false
				}
			}
		}
	}
	return current, nil
}

// goalLogDone projects numeric/checklist history against the current goal without
// rewriting the stored progress when a target or step definition is edited.
func goalLogDone(d *GoalDetails, l HabitLog) bool {
	result, _ := applyHabitProgress(d, l, l.Done, HabitProgressPatch{})
	return result.Done
}

func goalStreak(d *GoalDetails, logs []HabitLog, on, today time.Time) int {
	on = goalDay(on)
	today = goalDay(today)
	if on.After(today) {
		on = today
	}
	applicable := make([]HabitLog, 0, len(logs))
	for _, l := range logs {
		date, err := goalDate(l.LoggedOn)
		if err == nil && !date.After(on) && goalDue(d, date) {
			applicable = append(applicable, l)
		}
	}
	sort.Slice(applicable, func(i, j int) bool { return applicable[i].LoggedOn > applicable[j].LoggedOn })
	expected, hasExpected := previousGoalDue(d, on)
	count := 0
	for _, l := range applicable {
		date, _ := goalDate(l.LoggedOn)
		// Today may remain pending; an explicit incomplete log still breaks streak.
		if hasExpected && expected.Equal(today) && date.Before(today) {
			expected, hasExpected = previousGoalDue(d, today.AddDate(0, 0, -1))
		}
		if d != nil && d.AutoFail && hasExpected && !date.Equal(expected) {
			return count
		}
		if !goalLogDone(d, l) {
			return count
		}
		count++
		expected, hasExpected = previousGoalDue(d, date.AddDate(0, 0, -1))
	}
	return count
}
