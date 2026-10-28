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

func TestOverallLevelUsesModeratelySevere(t *testing.T) {
	// PHQ-9 skor 15 = band 15-19 (moderately_severe), GAD-7 skor 10 = moderate.
	// Overall harus mengikuti level yang lebih berat.
	bundle, err := ScoreBundle(
		[]int{2, 2, 2, 2, 2, 2, 1, 2, 0},
		[]int{2, 2, 2, 2, 2, 0, 0},
	)
	if err != nil {
		t.Fatalf("ScoreBundle returned error: %v", err)
	}
	if bundle.PHQ9.Level != "moderately_severe" {
		t.Fatalf("PHQ-9 level = %s, want moderately_severe", bundle.PHQ9.Level)
	}
	if bundle.GAD7.Level != "moderate" {
		t.Fatalf("GAD-7 level = %s, want moderate", bundle.GAD7.Level)
	}
	if bundle.Overall != "moderately_severe" {
		t.Fatalf("overall = %s, want moderately_severe", bundle.Overall)
	}
}

func TestOverallLevelSevereBeatsModeratelySevere(t *testing.T) {
	// GAD-7 skor 15 = severe harus menang atas PHQ-9 moderately_severe.
	bundle, err := ScoreBundle(
		[]int{2, 2, 2, 2, 2, 2, 1, 2, 0},
		[]int{2, 3, 2, 2, 2, 2, 2},
	)
	if err != nil {
		t.Fatalf("ScoreBundle returned error: %v", err)
	}
	if bundle.GAD7.Level != "severe" {
		t.Fatalf("GAD-7 level = %s, want severe", bundle.GAD7.Level)
	}
	if bundle.Overall != "severe" {
		t.Fatalf("overall = %s, want severe", bundle.Overall)
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
	// Level keparahan berdasarkan skor total (1), bukan "crisis".
	// Crisis flag dan level keparahan adalah dua hal terpisah.
	if result.Level != "minimal" {
		t.Fatalf("level = %s, want minimal (skor 1)", result.Level)
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
