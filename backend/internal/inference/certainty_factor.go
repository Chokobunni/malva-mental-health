package inference

// ============================================================
// CERTAINTY FACTOR — model Shortliffe & Buchanan (1975, MYCIN).
// Standar paling umum dipakai pada sistem pakar TA di Indonesia
// dan internasional.
//
// Rumus inti:
//   Kombinasi paralel (CF >= 0, CF >= 0):
//     CF(A,B)   = CF(A) + CF(B) * (1 - CF(A))
//   Keduanya negatif:
//     CF(A,B)   = CF(A) + CF(B) * (1 + CF(A))
//   Tanda berbeda:
//     CF(A,B)   = (CF(A) + CF(B)) / (1 - min(|CF(A)|, |CF(B)|))
//
//  CF user dari jawaban PHQ-9/GAD-7 (0-3):
//   0 -> 0.0 (tidak sama sekali)
//   1 -> 0.3 (beberapa hari)
//   2 -> 0.6 (lebih dari separuh hari)
//   3 -> 0.9 (hampir setiap hari)
//
// Referensi paritas: lib/src/ai/certainty_factor.dart (Dart client).
// Harus identik — client & server wajib menghasilkan CF yang sama.
// ============================================================

// ScoreToCF mengubah jawaban mentah (0-3) menjadi CF user.
func ScoreToCF(rawScore int) float64 {
	switch rawScore {
	case 1:
		return 0.3
	case 2:
		return 0.6
	case 3:
		return 0.9
	default:
		return 0.0
	}
}

// Combine menggabungkan dua CF (kombinasi paralel).
func Combine(cf1, cf2 float64) float64 {
	cf1 = clamp(cf1, -1.0, 1.0)
	cf2 = clamp(cf2, -1.0, 1.0)
	if cf1 >= 0 && cf2 >= 0 {
		return cf1 + cf2*(1.0-cf1)
	}
	if cf1 < 0 && cf2 < 0 {
		return cf1 + cf2*(1.0+cf1)
	}
	pos, neg := cf1, cf2
	if cf1 < 0 {
		pos, neg = cf2, cf1
	}
	minAbs := pos
	if abs(neg) < abs(pos) {
		minAbs = abs(neg)
	}
	return (pos + neg) / (1.0 - abs(pos)*minAbs)
}

// CombineConditions menggabungkan CF antar-kondisi (AND logika).
// Kondisi dengan CF <= 0 dianggap gagal dan menghasilkan 0.
func CombineConditions(cfs []float64) float64 {
	if len(cfs) == 0 {
		return 0.0
	}
	positive := make([]float64, 0, len(cfs))
	for _, cf := range cfs {
		if cf > 0 {
			positive = append(positive, cf)
		}
	}
	if len(positive) == 0 {
		return 0.0
	}
	result := positive[0]
	for _, cf := range positive[1:] {
		result = Combine(result, cf)
	}
	return result
}

// ApplyRuleCF mengalikan CF pakar rule dengan CF gabungan kondisi.
// CF rule = CF(R) * CF(E); bila bukti gagal (<= 0) hasilnya 0.
func ApplyRuleCF(ruleCF, conditionsCF float64) float64 {
	if conditionsCF <= 0 {
		return 0.0
	}
	return ruleCF * conditionsCF
}

// LabelFor memberi label keterangan CF (untuk audit/log).
func LabelFor(cf float64) string {
	normalized := (cf + 1.0) / 2.0
	switch {
	case normalized < 0.2:
		return "Sangat Tidak Pasti"
	case normalized < 0.4:
		return "Tidak Pasti"
	case normalized < 0.6:
		return "Cukup Pasti"
	case normalized < 0.8:
		return "Pasti"
	default:
		return "Sangat Pasti"
	}
}

func clamp(v, lo, hi float64) float64 {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}

func abs(v float64) float64 {
	if v < 0 {
		return -v
	}
	return v
}
