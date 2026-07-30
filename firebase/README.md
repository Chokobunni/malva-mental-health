# Firebase Setup Notes

File ini berisi starter rules untuk role:

- `patient`
- `professional`
- `admin`

Gunakan Firebase custom claims untuk `request.auth.token.role`. Hubungan pasien-profesional disimpan di:

```txt
patient_professional_links/{patientId}_{professionalId}
```

Dokumen link minimal:

```json
{
  "patientId": "patient_uid",
  "professionalId": "professional_uid",
  "status": "active",
  "consentVersion": "2026.1",
  "createdAt": "serverTimestamp"
}
```

Rules ini adalah starter. Untuk produksi, tambahkan validasi schema memakai Cloud Functions atau Firestore Rules yang lebih ketat, terutama untuk assessment score, medication log, dan crisis alert.
