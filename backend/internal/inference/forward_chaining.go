// Package inference — Forward Chaining + Certainty Factor untuk
// screening PHQ-9 dan GAD-7 di sisi server.
//
// Engine ini adalah port 1:1 dari client Flutter
// (lib/src/ai/forward_chaining_engine.dart + knowledge_base.dart).
// Paritas wajib: jawaban yang sama HARUS menghasilkan level, CF,
// dan urutan rule yang identik — server diuji dengan vektor kasus
// yang sama seperti client (lihat inference_test.go).
//
// Alur Forward Chaining (data-driven):
//  1. Working memory diisi fakta dari jawaban pasien (CF per item).
//  2. Fakta total skor dihitung (phq9_total_score / gad7_total_score).
//  3. Rule base dievaluasi berulang; rule yang semua kondisinya
//     terpenuhi "menembak" (fire) dan menambah fakta baru.
//  4. Ulangi sampai tidak ada rule yang menembak (fixed point)
//     atau batas iterasi tercapai.
//  5. Kesimpulan akhir diambil dari fakta level terparah.
package inference

import (
	"fmt"
)

// RuleVersion versi rule base FC+CF (samakan dengan client).
const RuleVersion = "2026.1.FC"

// ConditionOperator operator pembanding kondisi rule.
type ConditionOperator string

const (
	OpEquals        ConditionOperator = "equals"
	OpNotEquals     ConditionOperator = "notEquals"
	OpGreaterThan   ConditionOperator = "greaterThan"
	OpGreaterOrEq   ConditionOperator = "greaterOrEqual"
	OpLessThan      ConditionOperator = "lessThan"
	OpLessOrEqual   ConditionOperator = "lessOrEqual"
)

// Condition kondisi IF pada rule.
type Condition struct {
	FactID string            `json:"fact_id"`
	Op     ConditionOperator `json:"operator"`
	Value  int               `json:"value"`
	MinCF  float64           `json:"min_cf"`
}

// Conclusion fakta baru yang dihasilkan rule (THEN).
type Conclusion struct {
	FactID      string  `json:"fact_id"`
	Value       string  `json:"value"`
	CF          float64 `json:"cf"`
	Explanation string  `json:"explanation"`
}

// Rule satu baris rule base pakar: IF conditions THEN conclusions
// dengan kepercayaan pakar RuleCF.
type Rule struct {
	ID          string       `json:"id"`
	Description string       `json:"description"`
	Conditions  []Condition  `json:"conditions"`
	Conclusions []Conclusion `json:"conclusions"`
	RuleCF      float64      `json:"rule_cf"`
}

// Fact fakta dalam working memory.
type Fact struct {
	FactID string  `json:"fact_id"`
	Value  int     `json:"value"`
	Str    string  `json:"str,omitempty"`
	CF     float64 `json:"cf"`
	Note   string  `json:"note,omitempty"`
}

// Trace jejak audit satu rule (fired atau tidak).
type Trace struct {
	RuleID       string   `json:"rule_id"`
	Description  string   `json:"description"`
	Fired        bool     `json:"fired"`
	ConditionCF  float64  `json:"condition_cf"`
	ResultCF     float64  `json:"result_cf"`
	Satisfied    []string `json:"satisfied,omitempty"`
	Failed       []string `json:"failed,omitempty"`
}

// InferenceResult hasil akhir inference.
type InferenceResult struct {
	Level          string          `json:"level"`
	CF             float64         `json:"cf"`
	Summary        string          `json:"summary"`
	IsCrisis       bool            `json:"is_crisis"`
	Trace          []Trace         `json:"trace"`
	WorkingMemory  map[string]Fact `json:"-"`
	FiredRuleCount int             `json:"fired_rule_count"`
}

// Engine forward chaining.
type Engine struct {
	MaxIterations int
}

// NewEngine membuat engine dengan batas iterasi aman.
func NewEngine() *Engine {
	return &Engine{MaxIterations: 100}
}

// Infer menjalankan forward chaining atas jawaban pasien.
func (e *Engine) Infer(questionIDs []string, answers []int, rules []Rule) (InferenceResult, error) {
	if len(questionIDs) != len(answers) {
		return InferenceResult{}, fmt.Errorf("question ids and answers must have the same length")
	}
	if e.MaxIterations <= 0 {
		e.MaxIterations = 100
	}

	wm := make(map[string]Fact, len(questionIDs)+8)
	for i, qid := range questionIDs {
		raw := answers[i]
		if raw < 0 || raw > 3 {
			return InferenceResult{}, fmt.Errorf("answer for %s must be between 0 and 3", qid)
		}
		wm[qid] = Fact{
			FactID: qid,
			Value:  raw,
			CF:     ScoreToCF(raw),
			Note:   fmt.Sprintf("Jawaban langsung dari pasien (skor %d)", raw),
		}
	}

	calcTotals(wm, questionIDs, "phq9", "phq_")
	calcTotals(wm, questionIDs, "gad7", "gad_")

	trace := make([]Trace, 0, len(rules))
	firedAny := true
	iterations := 0
	firedCount := 0
	for firedAny && iterations < e.MaxIterations {
		firedAny = false
		iterations++
		for _, rule := range rules {
			tr := evaluateRule(rule, wm)
			trace = append(trace, tr)
			if tr.Fired {
				firedAny = true
				firedCount++
				applyConclusions(rule, wm)
			}
		}
	}

	return buildResult(wm, trace, firedCount), nil
}

func calcTotals(wm map[string]Fact, questionIDs []string, prefix, questionPrefix string) {
	total := 0
	totalCF := 0.0
	count := 0
	for _, qid := range questionIDs {
		if len(qid) >= len(questionPrefix) && qid[:len(questionPrefix)] == questionPrefix {
			if fact, ok := wm[qid]; ok {
				total += fact.Value
				totalCF += fact.CF
				count++
			}
		}
	}
	if count > 0 {
		wm[prefix+"_total_score"] = Fact{
			FactID: prefix + "_total_score",
			Value:  total,
			CF:     totalCF / float64(count),
			Note:   fmt.Sprintf("Total skor %s: %d dari %d item", prefix, total, count),
		}
	}
}

func evaluateRule(rule Rule, wm map[string]Fact) Trace {
	tr := Trace{RuleID: rule.ID, Description: rule.Description}
	conditionCFs := make([]float64, 0, len(rule.Conditions))
	allSatisfied := true

	for _, cond := range rule.Conditions {
		fact, ok := wm[cond.FactID]
		if !ok {
			tr.Failed = append(tr.Failed,
				fmt.Sprintf("%s: fakta tidak ditemukan", cond.FactID))
			conditionCFs = append(conditionCFs, 0.0)
			allSatisfied = false
			continue
		}
		met := compareInt(fact.Value, cond.Op, cond.Value)
		cf := 0.0
		if met {
			cf = fact.CF
		}
		conditionCFs = append(conditionCFs, cf)
		desc := fmt.Sprintf("%s %s %d (CF=%.3f, min=%.2f)",
			cond.FactID, cond.Op, cond.Value, cf, cond.MinCF)
		if met && cf >= cond.MinCF {
			tr.Satisfied = append(tr.Satisfied, desc)
		} else {
			tr.Failed = append(tr.Failed, desc)
			allSatisfied = false
		}
	}

	tr.ConditionCF = CombineConditions(conditionCFs)
	if allSatisfied {
		tr.ResultCF = ApplyRuleCF(rule.RuleCF, tr.ConditionCF)
	}
	tr.Fired = allSatisfied
	return tr
}

func applyConclusions(rule Rule, wm map[string]Fact) {
	// Cari CF gabungan kondisi rule terakhir yang menembak
	// (dipakai ulang dari evaluasi trace terakhir rule ini).
	tr := evaluateRule(rule, wm)
	for _, concl := range rule.Conclusions {
		if existing, ok := wm[concl.FactID]; ok {
			wm[concl.FactID] = Fact{
				FactID: concl.FactID,
				Value:  existing.Value,
				Str:    concl.Value,
				CF:     Combine(existing.CF, tr.ResultCF),
				Note:   existing.Note + " + " + concl.Explanation,
			}
		} else {
			wm[concl.FactID] = Fact{
				FactID: concl.FactID,
				Str:    concl.Value,
				CF:     tr.ResultCF,
				Note:   concl.Explanation,
			}
		}
	}
}

func compareInt(value int, op ConditionOperator, target int) bool {
	switch op {
	case OpEquals:
		return value == target
	case OpNotEquals:
		return value != target
	case OpGreaterThan:
		return value > target
	case OpGreaterOrEq:
		return value >= target
	case OpLessThan:
		return value < target
	case OpLessOrEqual:
		return value <= target
	}
	return false
}

var levelPriority = map[string]int{
	"minimal":  0,
	"mild":     1,
	"moderate": 2,
	"severe":   3,
	"crisis":   4,
}

func buildResult(wm map[string]Fact, trace []Trace, firedCount int) InferenceResult {
	// Krisis: crisis_flag pernah dibuat oleh rule (Value disimpan 1 pada
	// applyConclusions untuk konklusi bertipe flag). Tandai via CF > 0.
	if crisis, ok := wm["crisis_flag"]; ok && crisis.CF > 0 {
		summary := "Ada indikator keselamatan diri. Tampilkan crisis flow dan hubungi profesional."
		if lvl, ok := wm["crisis_level"]; ok {
			summary = lvl.Str
		}
		return InferenceResult{
			Level:          "crisis",
			CF:             crisis.CF,
			Summary:        summary,
			IsCrisis:       true,
			Trace:          trace,
			WorkingMemory:  wm,
			FiredRuleCount: firedCount,
		}
	}

	dep, hasDep := wm["depression_level"]
	anx, hasAnx := wm["anxiety_level"]

	depPriority, anxPriority := 0, 0
	depLevel, anxLevel := "minimal", "minimal"
	if hasDep {
		depLevel = dep.Str
		depPriority = levelPriority[depLevel]
	}
	if hasAnx {
		anxLevel = anx.Str
		anxPriority = levelPriority[anxLevel]
	}

	res := InferenceResult{Trace: trace, WorkingMemory: wm, FiredRuleCount: firedCount}
	if depPriority >= anxPriority {
		res.Level = depLevel
		if hasDep {
			res.CF = dep.CF
			res.Summary = dep.Note
		}
	} else {
		res.Level = anxLevel
		if hasAnx {
			res.CF = anx.CF
			res.Summary = anx.Note
		}
	}
	if res.Summary == "" {
		res.Summary = "Gejala minimal."
	}
	return res
}
