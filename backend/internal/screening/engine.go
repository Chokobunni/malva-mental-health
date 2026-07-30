package screening

import (
	"errors"
	"fmt"
)

const RuleVersion = "2026.1"

type Answer struct {
	QuestionID string `json:"question_id"`
	Score      int    `json:"score"`
	Position   int    `json:"position"`
}

type Result struct {
	Type       string   `json:"type"`
	Score      int      `json:"score"`
	MaxScore   int      `json:"max_score"`
	Level      string   `json:"level"`
	Summary    string   `json:"summary"`
	CrisisFlag bool     `json:"crisis_flag"`
	Answers    []Answer `json:"answers"`
}

type Bundle struct {
	PHQ9        Result `json:"phq9"`
	GAD7        Result `json:"gad7"`
	Overall     string `json:"overall_level"`
	CrisisFlag  bool   `json:"crisis_flag"`
	RuleVersion string `json:"rule_version"`
}

var phq9Questions = []string{
	"phq_interest",
	"phq_low_mood",
	"phq_sleep",
	"phq_energy",
	"phq_appetite",
	"phq_self_worth",
	"phq_focus",
	"phq_motor",
	"phq_self_harm",
}

var gad7Questions = []string{
	"gad_nervous",
	"gad_control",
	"gad_worry",
	"gad_relax",
	"gad_restless",
	"gad_irritable",
	"gad_fear",
}

func ScoreBundle(phq9Answers, gad7Answers []int) (Bundle, error) {
	phq9, err := Score("phq9", phq9Answers)
	if err != nil {
		return Bundle{}, err
	}
	gad7, err := Score("gad7", gad7Answers)
	if err != nil {
		return Bundle{}, err
	}
	return Bundle{
		PHQ9:        phq9,
		GAD7:        gad7,
		Overall:     overallLevel(phq9, gad7),
		CrisisFlag:  phq9.CrisisFlag || gad7.CrisisFlag,
		RuleVersion: RuleVersion,
	}, nil
}

func Score(kind string, values []int) (Result, error) {
	var questions []string
	var maxScore int
	switch kind {
	case "phq9":
		questions = phq9Questions
		maxScore = 27
	case "gad7":
		questions = gad7Questions
		maxScore = 21
	default:
		return Result{}, fmt.Errorf("unsupported assessment type %q", kind)
	}
	if len(values) != len(questions) {
		return Result{}, fmt.Errorf("%s expects %d answers", kind, len(questions))
	}
	total := 0
	answers := make([]Answer, 0, len(values))
	for index, value := range values {
		if value < 0 || value > 3 {
			return Result{}, errors.New("assessment answers must be between 0 and 3")
		}
		total += value
		answers = append(answers, Answer{
			QuestionID: questions[index],
			Score:      value,
			Position:   index + 1,
		})
	}

	level, summary := riskFor(kind, total)
	crisis := kind == "phq9" && values[8] > 0
	if crisis {
		level = "crisis"
		summary = "Ada indikator keselamatan diri. Tampilkan crisis flow dan hubungi profesional."
	}
	return Result{
		Type:       kind,
		Score:      total,
		MaxScore:   maxScore,
		Level:      level,
		Summary:    summary,
		CrisisFlag: crisis,
		Answers:    answers,
	}, nil
}

func riskFor(kind string, total int) (string, string) {
	if kind == "phq9" {
		switch {
		case total <= 4:
			return "minimal", "Gejala depresi minimal. Pantau pola mood dan rutinitas."
		case total <= 9:
			return "mild", "Gejala ringan. Ulangi asesmen dan diskusikan bila menetap."
		case total <= 14:
			return "moderate", "Gejala sedang. Perlu review profesional dan rencana tindak lanjut."
		case total <= 19:
			return "severe", "Gejala cukup berat. Prioritaskan evaluasi profesional."
		default:
			return "severe", "Gejala berat. Butuh review klinis segera."
		}
	}
	switch {
	case total <= 4:
		return "minimal", "Gejala kecemasan minimal. Lanjutkan pemantauan rutin."
	case total <= 9:
		return "mild", "Gejala ringan. Ulangi asesmen pada follow-up."
	case total <= 14:
		return "moderate", "Gejala sedang. Perlu evaluasi profesional."
	default:
		return "severe", "Gejala berat. Prioritaskan review klinis dan rencana dukungan."
	}
}

func overallLevel(phq9, gad7 Result) string {
	if phq9.CrisisFlag || gad7.CrisisFlag {
		return "crisis"
	}
	priority := map[string]int{
		"minimal":  0,
		"mild":     1,
		"moderate": 2,
		"severe":   3,
		"crisis":   4,
	}
	if priority[phq9.Level] >= priority[gad7.Level] {
		return phq9.Level
	}
	return gad7.Level
}
