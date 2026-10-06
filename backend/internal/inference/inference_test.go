package inference

import (
	"math"
	"testing"
)

func runPHQ9(t *testing.T, answers []int) InferenceResult {
	t.Helper()
	engine := NewEngine()
	res, err := engine.Infer(PHQ9QuestionIDs, answers, PHQ9Rules())
	if err != nil {
		t.Fatalf("infer: %v", err)
	}
	return res
}

func runGAD7(t *testing.T, answers []int) InferenceResult {
	t.Helper()
	engine := NewEngine()
	res, err := engine.Infer(GAD7QuestionIDs, answers, GAD7Rules())
	if err != nil {
		t.Fatalf("infer: %v", err)
	}
	return res
}

func TestPHQ9SeverityLevels(t *testing.T) {
	cases := []struct {
		name     string
		answers  []int
		expected string
	}{
		{"minimal (0-4)", []int{0, 0, 0, 0, 0, 0, 0, 3, 0}, "minimal"},
		{"mild (5-9)", []int{1, 1, 1, 1, 1, 0, 0, 0, 0}, "mild"},
		{"moderate (10-14)", []int{2, 2, 1, 2, 1, 1, 1, 0, 0}, "moderate"},
		{"moderately severe (15-19)", []int{2, 2, 2, 2, 2, 2, 1, 2, 0}, "severe"},
		{"severe (20-27)", []int{3, 3, 2, 3, 2, 3, 2, 2, 0}, "severe"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			res := runPHQ9(t, tc.answers)
			if res.Level != tc.expected {
				t.Errorf("level = %s, want %s", res.Level, tc.expected)
			}
			if res.CF <= 0.0 || res.CF > 1.0 {
				t.Errorf("CF = %.3f, want (0, 1]", res.CF)
			}
			if res.IsCrisis {
				t.Errorf("crisis tidak diharapkan untuk jawaban item9=0")
			}
			if res.FiredRuleCount == 0 {
				t.Errorf("minimal satu rule harus menembak")
			}
		})
	}
}

func TestPHQ9SelfHarmSetsCrisis(t *testing.T) {
	// Skor total rendah tapi item 9 positif -> tetap krisis.
	res := runPHQ9(t, []int{0, 0, 0, 0, 0, 0, 0, 0, 1})
	if !res.IsCrisis || res.Level != "crisis" {
		t.Fatalf("want crisis, got level=%s isCrisis=%v", res.Level, res.IsCrisis)
	}
	if res.CF < 0.9 {
		t.Errorf("CF krisis harus tinggi (>= 0.9), got %.3f", res.CF)
	}
	// Cari trace rule krisis.
	found := false
	for _, tr := range res.Trace {
		if tr.RuleID == "PHQ9_CRISIS_SELF_HARM" && tr.Fired {
			found = true
		}
	}
	if !found {
		t.Errorf("rule PHQ9_CRISIS_SELF_HARM harus menembak")
	}
}

func TestGAD7SeverityLevels(t *testing.T) {
	cases := []struct {
		name     string
		answers  []int
		expected string
	}{
		{"minimal (0-4)", []int{1, 0, 1, 0, 1, 0, 1}, "minimal"},
		{"mild (5-9)", []int{1, 1, 1, 1, 1, 0, 0}, "mild"},
		{"moderate (10-14)", []int{2, 2, 1, 2, 1, 1, 1}, "moderate"},
		{"severe (15-21)", []int{2, 3, 2, 2, 2, 2, 2}, "severe"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			res := runGAD7(t, tc.answers)
			if res.Level != tc.expected {
				t.Errorf("level = %s, want %s", res.Level, tc.expected)
			}
		})
	}
}

func TestTraceContainsAuditTrail(t *testing.T) {
	res := runPHQ9(t, []int{2, 2, 2, 2, 2, 2, 2, 2, 0})
	if len(res.Trace) == 0 {
		t.Fatalf("trace tidak boleh kosong")
	}
	firedAny := false
	for _, tr := range res.Trace {
		if tr.Fired {
			firedAny = true
			if tr.ResultCF <= 0 {
				t.Errorf("%s menembak tapi ResultCF=%.3f", tr.RuleID, tr.ResultCF)
			}
		}
	}
	if !firedAny {
		t.Errorf("minimal satu rule harus menembak")
	}
}

func TestCFCombineMatchesReference(t *testing.T) {
	// Rumus kombinasi paralel standar: 0.6 + 0.9*(1-0.6) = 0.96.
	got := Combine(0.6, 0.9)
	if math.Abs(got-0.96) > 1e-9 {
		t.Errorf("Combine(0.6, 0.9) = %.6f, want 0.96", got)
	}
	// 0.3 + 0.3*(1-0.3) = 0.51.
	if got := Combine(0.3, 0.3); math.Abs(got-0.51) > 1e-9 {
		t.Errorf("Combine(0.3, 0.3) = %.6f, want 0.51", got)
	}
	// CF 0 tidak mengubah.
	if got := Combine(0.0, 0.6); math.Abs(got-0.6) > 1e-9 {
		t.Errorf("Combine(0, 0.6) = %.6f, want 0.6", got)
	}
}

func TestCFScoreMapping(t *testing.T) {
	want := []float64{0.0, 0.3, 0.6, 0.9}
	for score, expect := range want {
		if got := ScoreToCF(score); math.Abs(got-expect) > 1e-9 {
			t.Errorf("ScoreToCF(%d) = %.2f, want %.2f", score, got, expect)
		}
	}
}

func TestErrors(t *testing.T) {
	engine := NewEngine()
	if _, err := engine.Infer(PHQ9QuestionIDs[:3], []int{0, 0}, PHQ9Rules()); err == nil {
		t.Errorf("mismatched lengths harus error")
	}
	if _, err := engine.Infer(PHQ9QuestionIDs, []int{0, 0, 0, 0, 0, 0, 0, 0, 4}, PHQ9Rules()); err == nil {
		t.Errorf("answer > 3 harus error")
	}
	if _, err := engine.Infer(PHQ9QuestionIDs, []int{0, 0, 0, 0, 0, 0, 0, 0, -1}, PHQ9Rules()); err == nil {
		t.Errorf("answer < 0 harus error")
	}
}

func TestWorkingMemoryFacts(t *testing.T) {
	// phq_sleep=2 men-trigger rule turunan gangguan tidur (chaining).
	res := runPHQ9(t, []int{1, 1, 2, 1, 1, 1, 1, 1, 0})
	if _, ok := res.WorkingMemory["phq9_total_score"]; !ok {
		t.Errorf("phq9_total_score harus ada di working memory")
	}
	fact := res.WorkingMemory["phq9_total_score"]
	if fact.Value != 9 {
		t.Errorf("total = %d, want 9", fact.Value)
	}
	if _, ok := res.WorkingMemory["sleep_disruption_present"]; !ok {
		t.Errorf("fakta turunan sleep_disruption_present harus ada (chaining)")
	}
	if res.Trace == nil && len(res.Trace) == 0 {
		t.Errorf("trace harus ada")
	}
}
