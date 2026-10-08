package inference

// ============================================================
// KNOWLEDGE BASE — Rule base pakar FC+CF untuk PHQ-9 & GAD-7.
//
// Sumber standar:
//  - Kroenke, Spitzer & Williams (2001): PHQ-9 cut-off 5/10/15/20
//    (minimal / mild / moderate / moderately severe / severe).
//  - Spitzer, Kroenke, Williams & Löwe (2006): GAD-7 cut-off 5/10/15
//    (minimal / mild / moderate / severe).
//  - DSM-5: item 9 PHQ-9 (pikiran menyakiti diri) = red flag krisis
//    terlepas dari total skor.
//  - Permenkes No. KP.04.05/…/2019: standar layanan kesehatan jiwa
//    di faskes Indonesia memakai alat deteksi dini PHQ-9/GAD-7.
//
// CF pakar (ruleCF) memodelkan keandalan rule klinis:
//  - 0.95: rentang cut-off baku instrumen (sangat andal)
//  - 0.90: pola gejala dominan (andung didukung literatur)
//  - 0.85: pola sekunder (pendukung)
// CF user mengikuti mapping jawaban 0-3 -> 0/0.3/0.6/0.9.
// Port 1:1 dari lib/src/ai/knowledge_base.dart (client).
// ============================================================

// PHQ9QuestionIDs urutan item PHQ-9.
var PHQ9QuestionIDs = []string{
	"phq_interest", "phq_low_mood", "phq_sleep", "phq_energy",
	"phq_appetite", "phq_self_worth", "phq_focus", "phq_motor",
	"phq_self_harm",
}

// GAD7QuestionIDs urutan item GAD-7.
var GAD7QuestionIDs = []string{
	"gad_nervous", "gad_control", "gad_worry", "gad_relax",
	"gad_restless", "gad_irritable", "gad_fear",
}

// PHQ9Rules rule base depresi (PHQ-9).
func PHQ9Rules() []Rule {
	return []Rule{
		{
			ID:          "PHQ9_MINIMAL",
			Description: "Gejala depresi minimal (skor 0-4)",
			Conditions: []Condition{
				{FactID: "phq9_total_score", Op: OpLessOrEqual, Value: 4},
			},
			Conclusions: []Conclusion{
				{FactID: "depression_level", Value: "minimal", CF: 0.9,
					Explanation: "Skor PHQ-9 ≤ 4 menunjukkan gejala depresi minimal"},
				{FactID: "depression_summary", Value: "minimal", CF: 0.9,
					Explanation: "Gejala depresi minimal. Pantau pola mood dan rutinitas."},
			},
			RuleCF: 0.60,
		},
		{
			ID:          "PHQ9_MILD",
			Description: "Gejala depresi ringan (skor 5-9)",
			Conditions: []Condition{
				{FactID: "phq9_total_score", Op: OpGreaterOrEq, Value: 5},
				{FactID: "phq9_total_score", Op: OpLessOrEqual, Value: 9},
			},
			Conclusions: []Conclusion{
				{FactID: "depression_level", Value: "mild", CF: 0.85,
					Explanation: "Skor PHQ-9 5-9 menunjukkan gejala depresi ringan"},
				{FactID: "depression_summary", Value: "mild", CF: 0.85,
					Explanation: "Gejala ringan. Ulangi asesmen dan diskusikan bila menetap."},
			},
			RuleCF: 0.72,
		},
		{
			ID:          "PHQ9_MODERATE",
			Description: "Gejala depresi sedang (skor 10-14)",
			Conditions: []Condition{
				{FactID: "phq9_total_score", Op: OpGreaterOrEq, Value: 10},
				{FactID: "phq9_total_score", Op: OpLessOrEqual, Value: 14},
			},
			Conclusions: []Conclusion{
				{FactID: "depression_level", Value: "moderate", CF: 0.9,
					Explanation: "Skor PHQ-9 10-14 menunjukkan gejala depresi sedang"},
				{FactID: "depression_summary", Value: "moderate", CF: 0.9,
					Explanation: "Gejala sedang. Perlu review profesional dan rencana tindak lanjut."},
			},
			RuleCF: 0.84,
		},
		{
			ID:          "PHQ9_SEVERE_MODERATE",
			Description: "Gejala depresi cukup berat (skor 15-19)",
			Conditions: []Condition{
				{FactID: "phq9_total_score", Op: OpGreaterOrEq, Value: 15},
				{FactID: "phq9_total_score", Op: OpLessOrEqual, Value: 19},
			},
			Conclusions: []Conclusion{
				{FactID: "depression_level", Value: "severe", CF: 0.9,
					Explanation: "Skor PHQ-9 15-19 menunjukkan gejala depresi cukup berat"},
				{FactID: "depression_summary", Value: "severe", CF: 0.9,
					Explanation: "Gejala cukup berat. Prioritaskan evaluasi profesional."},
			},
			RuleCF: 0.90,
		},
		{
			ID:          "PHQ9_SEVERE_HIGH",
			Description: "Gejala depresi berat (skor 20-27)",
			Conditions: []Condition{
				{FactID: "phq9_total_score", Op: OpGreaterOrEq, Value: 20},
			},
			Conclusions: []Conclusion{
				{FactID: "depression_level", Value: "severe", CF: 0.95,
					Explanation: "Skor PHQ-9 20-27 menunjukkan gejala depresi berat"},
				{FactID: "depression_summary", Value: "severe", CF: 0.95,
					Explanation: "Gejala berat. Butuh review klinis segera."},
			},
			RuleCF: 0.95,
		},
		{
			// DSM-5 red flag: item 9 > 0 selalu krisis.
			ID:          "PHQ9_CRISIS_SELF_HARM",
			Description: "Red flag keselamatan: pikiran menyakiti diri (item 9 > 0)",
			Conditions: []Condition{
				{FactID: "phq_self_harm", Op: OpGreaterThan, Value: 0, MinCF: 0.0},
			},
			Conclusions: []Conclusion{
				{FactID: "crisis_flag", Value: "crisis", CF: 0.95,
					Explanation: "Pasien melaporkan pikiran menyakiti diri"},
				{FactID: "crisis_level", Value: "crisis", CF: 0.95,
					Explanation: "Ada indikator keselamatan diri. Tampilkan crisis flow dan hubungi profesional."},
			},
			RuleCF: 1.0,
		},
		{
			ID:          "PHQ9_MOTOR_RETARDATION",
			Description: "Pola gejala: retardasi/agitasi psikomotor",
			Conditions: []Condition{
				{FactID: "phq_motor", Op: OpGreaterOrEq, Value: 2, MinCF: 0.0},
			},
			Conclusions: []Conclusion{
				{FactID: "motor_retardation_present", Value: "present", CF: 0.8,
					Explanation: "Gejala psikomotor hadir (≥ 2)"},
			},
			RuleCF: 0.8,
		},
		{
			ID:          "PHQ9_SLEEP_DISRUPTION",
			Description: "Pola gejala: gangguan tidur",
			Conditions: []Condition{
				{FactID: "phq_sleep", Op: OpGreaterOrEq, Value: 2, MinCF: 0.0},
			},
			Conclusions: []Conclusion{
				{FactID: "sleep_disruption_present", Value: "present", CF: 0.8,
					Explanation: "Gangguan tidur hadir (≥ 2)"},
			},
			RuleCF: 0.85,
		},
		{
			ID:          "PHQ9_APPETITE_CHANGE",
			Description: "Pola gejala: perubahan nafsu makan",
			Conditions: []Condition{
				{FactID: "phq_appetite", Op: OpGreaterOrEq, Value: 2, MinCF: 0.0},
			},
			Conclusions: []Conclusion{
				{FactID: "appetite_change_present", Value: "present", CF: 0.8,
					Explanation: "Perubahan nafsu makan hadir (≥ 2)"},
			},
			RuleCF: 0.8,
		},
		{
			ID:          "PHQ9_CONCENTRATION_ISSUE",
			Description: "Pola gejala: gangguan konsentrasi",
			Conditions: []Condition{
				{FactID: "phq_focus", Op: OpGreaterOrEq, Value: 2, MinCF: 0.0},
			},
			Conclusions: []Conclusion{
				{FactID: "concentration_issue_present", Value: "present", CF: 0.8,
					Explanation: "Gangguan konsentrasi hadir (≥ 2)"},
			},
			RuleCF: 0.8,
		},
		{
			ID:          "PHQ9_SELF_WORTH_ISSUE",
			Description: "Pola gejala: harga diri rendah / rasa bersalah",
			Conditions: []Condition{
				{FactID: "phq_self_worth", Op: OpGreaterOrEq, Value: 2, MinCF: 0.0},
			},
			Conclusions: []Conclusion{
				{FactID: "self_worth_issue_present", Value: "present", CF: 0.8,
					Explanation: "Masalah harga diri / rasa bersalah hadir (≥ 2)"},
			},
			RuleCF: 0.85,
		},
	}
}

// GAD7Rules rule base kecemasan (GAD-7).
func GAD7Rules() []Rule {
	return []Rule{
		{
			ID:          "GAD7_MINIMAL",
			Description: "Gejala kecemasan minimal (skor 0-4)",
			Conditions: []Condition{
				{FactID: "gad7_total_score", Op: OpLessOrEqual, Value: 4},
			},
			Conclusions: []Conclusion{
				{FactID: "anxiety_level", Value: "minimal", CF: 0.9,
					Explanation: "Skor GAD-7 ≤ 4 menunjukkan gejala kecemasan minimal"},
				{FactID: "anxiety_summary", Value: "minimal", CF: 0.9,
					Explanation: "Gejala kecemasan minimal. Lanjutkan pemantauan rutin."},
			},
			RuleCF: 0.60,
		},
		{
			ID:          "GAD7_MILD",
			Description: "Gejala kecemasan ringan (skor 5-9)",
			Conditions: []Condition{
				{FactID: "gad7_total_score", Op: OpGreaterOrEq, Value: 5},
				{FactID: "gad7_total_score", Op: OpLessOrEqual, Value: 9},
			},
			Conclusions: []Conclusion{
				{FactID: "anxiety_level", Value: "mild", CF: 0.85,
					Explanation: "Skor GAD-7 5-9 menunjukkan gejala kecemasan ringan"},
				{FactID: "anxiety_summary", Value: "mild", CF: 0.85,
					Explanation: "Gejala ringan. Ulangi asesmen pada follow-up."},
			},
			RuleCF: 0.72,
		},
		{
			ID:          "GAD7_MODERATE",
			Description: "Gejala kecemasan sedang (skor 10-14)",
			Conditions: []Condition{
				{FactID: "gad7_total_score", Op: OpGreaterOrEq, Value: 10},
				{FactID: "gad7_total_score", Op: OpLessOrEqual, Value: 14},
			},
			Conclusions: []Conclusion{
				{FactID: "anxiety_level", Value: "moderate", CF: 0.9,
					Explanation: "Skor GAD-7 10-14 menunjukkan gejala kecemasan sedang"},
				{FactID: "anxiety_summary", Value: "moderate", CF: 0.9,
					Explanation: "Gejala sedang. Perlu evaluasi profesional."},
			},
			RuleCF: 0.84,
		},
		{
			ID:          "GAD7_SEVERE",
			Description: "Gejala kecemasan berat (skor 15-21)",
			Conditions: []Condition{
				{FactID: "gad7_total_score", Op: OpGreaterOrEq, Value: 15},
			},
			Conclusions: []Conclusion{
				{FactID: "anxiety_level", Value: "severe", CF: 0.92,
					Explanation: "Skor GAD-7 15-21 menunjukkan gejala kecemasan berat"},
				{FactID: "anxiety_summary", Value: "severe", CF: 0.92,
					Explanation: "Gejala berat. Prioritaskan review klinis dan rencana dukungan."},
			},
			RuleCF: 0.90,
		},
		{
			ID:          "GAD7_WORRY_RUMINATION",
			Description: "Pola gejala: ruminasi / sulit mengontrol khawatir",
			Conditions: []Condition{
				{FactID: "gad_worry", Op: OpGreaterOrEq, Value: 2, MinCF: 0.0},
				{FactID: "gad_control", Op: OpGreaterOrEq, Value: 2, MinCF: 0.0},
			},
			Conclusions: []Conclusion{
				{FactID: "worry_rumination_present", Value: "present", CF: 0.85,
					Explanation: "Ruminasi & khawatir sulit dikontrol hadir"},
			},
			RuleCF: 0.85,
		},
		{
			ID:          "GAD7_RESTLESSNESS",
			Description: "Pola gejala: gelisah & sulit rileks",
			Conditions: []Condition{
				{FactID: "gad_restless", Op: OpGreaterOrEq, Value: 2, MinCF: 0.0},
				{FactID: "gad_relax", Op: OpGreaterOrEq, Value: 2, MinCF: 0.0},
			},
			Conclusions: []Conclusion{
				{FactID: "restlessness_present", Value: "present", CF: 0.85,
					Explanation: "Gelisah & sulit rileks hadir"},
			},
			RuleCF: 0.85,
		},
		{
			ID:          "GAD7_FEAR_ANSWER",
			Description: "Pola gejala: ketakutan sesuatu buruk terjadi",
			Conditions: []Condition{
				{FactID: "gad_fear", Op: OpGreaterOrEq, Value: 2, MinCF: 0.0},
			},
			Conclusions: []Conclusion{
				{FactID: "fear_present", Value: "present", CF: 0.8,
					Explanation: "Perasaan takut sesuatu buruk terjadi hadir"},
			},
			RuleCF: 0.8,
		},
	}
}
