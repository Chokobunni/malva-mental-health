package screening

import "testing"

func TestScoreBundleCombinesPHQ9AndGAD7(t *testing.T) {
	bundle, err := ScoreBundle(
		[]int{1, 1, 1, 1, 1, 0, 0, 0, 0},
		[]int{2, 2, 2, 2, 2, 0, 0},
	)
	if err != nil {
		t.Fatalf("ScoreBundle returned error: %v", err)
	}
	if bundle.PHQ9.Score != 5 || bundle.PHQ9.Level != "mild" {
		t.Fatalf("PHQ-9 = %d/%s, want 5/mild", bundle.PHQ9.Score, bundle.PHQ9.Level)
	}
	if bundle.GAD7.Score != 10 || bundle.GAD7.Level != "moderate" {
		t.Fatalf("GAD-7 = %d/%s, want 10/moderate", bundle.GAD7.Score, bundle.GAD7.Level)
	}
	if bundle.Overall != "moderate" {
		t.Fatalf("overall = %s, want moderate", bundle.Overall)
	}
	if bundle.CrisisFlag {
		t.Fatal("crisis flag should be false")
	}
}

func TestPHQ9SelfHarmAnswerSetsCrisis(t *testing.T) {
	result, err := Score("phq9", []int{0, 0, 0, 0, 0, 0, 0, 0, 1})
	if err != nil {
		t.Fatalf("Score returned error: %v", err)
	}
	if !result.CrisisFlag {
		t.Fatal("crisis flag should be true")
	}
	if result.Level != "crisis" {
		t.Fatalf("level = %s, want crisis", result.Level)
	}
}

func TestScoreRejectsWrongAnswerCount(t *testing.T) {
	if _, err := Score("gad7", []int{0, 1}); err == nil {
		t.Fatal("expected error for wrong answer count")
	}
}

func TestScoreRejectsOutOfRangeAnswer(t *testing.T) {
	if _, err := Score("gad7", []int{0, 0, 0, 0, 0, 0, 4}); err == nil {
		t.Fatal("expected error for out-of-range answer")
	}
}
