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

func TestCombineConditionsUsesMin(t *testing.T) {
	// Konjungsi (AND): CF(A AND B) = min(CF(A), CF(B)).
	if got := CombineConditions([]float64{0.9, 0.4}); math.Abs(got-0.4) > 1e-9 {
		t.Errorf("CombineConditions([0.9,0.4]) = %.4f, want 0.4 (min)", got)
	}
	if got := CombineConditions([]float64{0.6, 0.4, 0.5}); math.Abs(got-0.4) > 1e-9 {
		t.Errorf("CombineConditions([0.6,0.4,0.5]) = %.4f, want 0.4 (min)", got)
	}
	// Kondisi gagal memblokir rule.
	if got := CombineConditions([]float64{0.9, 0.0}); got != 0.0 {
		t.Errorf("CombineConditions([0.9,0.0]) = %.4f, want 0.0", got)
	}
}

func TestNoRepeatedFiring(t *testing.T) {
	// Rule tidak boleh menembak berulang: CF hasil akhir harus wajar
	// (bukan konvergen ke 1.0 karena penggabungan berulang).
	res := runPHQ9(t, []int{0, 0, 0, 0, 0, 0, 0, 0, 0})
	if res.CF >= 1.0 {
		t.Errorf("CF = %.4f, seharusnya < 1.0 (tidak menembak berulang)", res.CF)
	}
	seen := map[string]bool{}
	for _, tr := range res.Trace {
		if !tr.Fired {
			continue
		}
		if seen[tr.RuleID] {
			t.Errorf("rule %s menembak lebih dari sekali (fire-once dilanggar)", tr.RuleID)
		}
		seen[tr.RuleID] = true
	}
}

func TestCFScoreMapping(t *testing.T) {
	want := []float64{0.0, 0.3, 0.6, 0.9}
	for score, expect := range want {
		if got := ScoreToCF(score); math.Abs(got-expect) > 1e-9 {
			t.Errorf("ScoreToCF(%d) = %.2f, want %.2f", score, got, expect)
		}
	}
	// Label kategori CF harus konsisten dgn skala (dipakai di audit).
	if LabelFor(0.95) != "Sangat Pasti" {
		t.Errorf("LabelFor(0.95) = %s, want Sangat Pasti", LabelFor(0.95))
	}
	if LabelFor(0.5) != "Pasti" {
		t.Errorf("LabelFor(0.5) = %s, want Pasti", LabelFor(0.5))
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

// TestParityVector mengunci hasil engine Go agar identik dengan engine
// Dart (client). Nilai harapan diambil dari test Dart
// test/ai_engine_test.dart (group 'Parity vektor') — kedua engine wajib
// menghasilkan level, CF, dan jumlah rule yang menembak yang sama persis.
func TestParityVector(t *testing.T) {
	cases := []struct {
		name      string
		answers   []int
		wantLevel string
		wantCF    float64
		wantFired int
	}{
		{"all zero", []int{0, 0, 0, 0, 0, 0, 0, 0, 0}, "minimal", 0.9025, 1},
		{"item9 = 1", []int{0, 0, 0, 0, 0, 0, 0, 0, 1}, "crisis", 0.9500, 2},
		{"moderate", []int{2, 2, 1, 2, 1, 1, 1, 0, 0}, "moderate", 0.9025, 1},
		{"all two", []int{2, 2, 2, 2, 2, 2, 2, 2, 2}, "crisis", 0.9500, 7},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			res := runPHQ9(t, tc.answers)
			if res.Level != tc.wantLevel {
				t.Errorf("level = %s, want %s", res.Level, tc.wantLevel)
			}
			if math.Abs(res.CF-tc.wantCF) > 0.001 {
				t.Errorf("CF = %.4f, want %.4f", res.CF, tc.wantCF)
			}
			if res.FiredRuleCount != tc.wantFired {
				t.Errorf("fired = %d, want %d", res.FiredRuleCount, tc.wantFired)
			}
		})
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
