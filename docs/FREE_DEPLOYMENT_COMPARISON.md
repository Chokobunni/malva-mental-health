# Free Deployment Comparison for Malva

Last checked: 2026-07-11

Malva saat ini adalah Flutter app. Untuk web, output deploy-nya adalah static files dari:

```powershell
flutter build web
```

Folder yang dipublish:

```text
build/web
```

## Kesimpulan Singkat

Pilihan terbaik tanpa bayar untuk Malva sekarang:

1. **Cloudflare Pages** - terbaik untuk deploy Flutter Web gratis dari GitHub.
2. **GitHub Pages** - paling sederhana, bagus untuk demo publik, tetapi repo public diperlukan pada GitHub Free.
3. **Vercel Hobby** - bisa, tetapi lebih cocok untuk Next.js/React; tetap oke untuk static Flutter Web.
4. **Lovable** - bukan pilihan utama untuk project Flutter existing; lebih cocok untuk build/prototype di platform Lovable.
5. **Heroku** - tidak cocok jika syaratnya benar-benar gratis, karena dyno termurah yang tercantum berbayar.

## Tabel Perbandingan

| Platform | Benar-benar gratis untuk Malva? | Cocok untuk Flutter Web static? | Kelebihan | Kekurangan | Catatan |
|---|---:|---:|---|---|---|
| Cloudflare Pages | Ya, untuk batas free tier | Ya | 500 builds/bulan pada Free plan, unlimited active preview deployments, global CDN, custom domains tinggi untuk free plan | Build command Flutter kadang perlu konfigurasi manual atau deploy hasil `build/web` | Rekomendasi utama |
| GitHub Pages | Ya untuk public repo di GitHub Free | Ya | Paling sederhana, langsung dari GitHub, cocok untuk demo | Private repo Pages butuh plan berbayar, hanya static hosting | Bagus jika repo boleh public |
| Vercel Hobby | Ya untuk personal/hobby | Ya | CI/CD mudah, CDN global, 100 GB fast data transfer/month tercantum di pricing | Limit dan kebijakan fair use; lebih diarahkan ke web framework seperti Next.js | Opsi kedua/ketiga |
| Lovable | Terbatas oleh credits | Tidak ideal untuk Flutter existing | Bisa cepat untuk prototype dan AI-assisted build | Free plan berbasis credits; bukan host Flutter source existing secara natural | Jangan jadikan host utama Malva Flutter |
| Heroku | Tidak | Bisa hanya jika dibuat server sendiri | Cocok untuk backend/server apps | Eco dyno tercantum $5/bulan; bukan static host terbaik | Tidak memenuhi syarat tanpa bayar |

## Rekomendasi untuk Malva

### Deploy web demo gratis

Gunakan **Cloudflare Pages**.

Alasan:

- Flutter Web adalah static output.
- Cloudflare Pages memang kuat untuk static hosting.
- Free plan cukup untuk demo development Malva.
- Preview deployment membantu sebelum dianggap final.

### Repository GitHub

Gunakan branch:

```text
develop
```

Jangan deploy dari branch `main` dulu kalau kamu belum mau project dianggap final.

### Database gratis untuk MVP

Gunakan Firebase Spark:

- Firebase Auth untuk login email/password.
- Cloud Firestore untuk data pasien.
- Firebase Security Rules untuk isolasi akses.
- Firebase Cloud Messaging sebagai kanal push.

Catatan kritis:

- Free tier cukup untuk MVP/testing kecil, bukan jaminan produksi skala besar.
- Cloud Functions bukan pilihan gratis di Spark; untuk medication reminder gratis, mulai dari local scheduled notification di device.

## Sumber Resmi

- Firebase Pricing: https://firebase.google.com/pricing
- Cloudflare Pages Limits: https://developers.cloudflare.com/pages/platform/limits/
- GitHub Pages Docs: https://docs.github.com/en/pages/getting-started-with-github-pages/what-is-github-pages
- Vercel Pricing: https://vercel.com/pricing
- Heroku Pricing: https://www.heroku.com/pricing/
- Lovable Pricing: https://lovable.dev/pricing
