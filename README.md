# BK Journal

Her gün tüm projelerinizdeki git commit'lerinizi toplayıp Obsidian günlük notunuza **çalışma özeti** olarak yazan, haftada bir de staj/ders raporuna yapıştırılabilecek **haftalık rapor** üreten bir macOS komut satırı aracı.

## Nasıl çalışır

1. `config.json` içindeki köklerin (varsayılan `~/Documents/GitHub`, `~/IdeaProjects`) altında en fazla 3 klasör derinliğinde git depolarını bulur. `node_modules`, `.build`, `build`, `Pods` gibi klasörlere ve gizli klasörlere girmez.
2. İstenen günün (yerel saatle 00:00–24:00) commit'lerini tüm dallardan toplar. Yalnızca sizin commit'leriniz alınır: `git config --global user.email` / `user.name` ve ayarlardaki ek adresler.
3. Özeti günlük notunuza, yalnızca kendi işaretleri arasına yazar.

```markdown
<!-- bk-journal:start -->
## Çalışma Özeti

**3 commit, 2 proje, +135 / −37 satır**

### bk-clean
- 10:00 README güncellendi · `main` (+5/−5)

### [[10 Projeler/Trafik360/Trafik360|Trafik360]]
- 09:05 Giriş hatası düzeltildi · `main` (+10/−2)
- 14:30 Harita katmanı eklendi · `ozellik/harita` (+120/−30)

**Commit edilmemiş değişiklikler**
- biore: 1 değişen, 2 izlenmeyen dosya
<!-- bk-journal:end -->
```

## Komutlar

| Komut | Ne yapar |
|---|---|
| `bkjournal yaz [--tarih YYYY-MM-DD] [--kuru]` | Bir günün özetini günlük nota yazar (varsayılan: bugün). |
| `bkjournal hafta [--tarih YYYY-MM-DD] [--kuru]` | O günü içeren ISO haftasının (Pzt–Paz) raporunu yazar. |
| `bkjournal tamamla [--kuru]` | Son başarılı çalışmadan bu yana eksik günleri (en fazla 7) tamamlar; biten haftanın raporunu da yazar. Zamanlayıcı bunu çalıştırır. |
| `bkjournal kur` | Her gün ayarlanan saatte (varsayılan 23:30) `bkjournal tamamla` çalıştıran LaunchAgent'ı kurar. |
| `bkjournal kaldir` | Zamanlayıcıyı kaldırır. |
| `bkjournal durum` | Ayarları, kasayı, son çalışmayı ve zamanlayıcı durumunu gösterir. |

`--kuru` hiçbir şey yazmaz (ayar dosyası bile oluşturmaz); bloğu, hedef dosyayı ve ne yapılacağını gösterir. İngilizce karşılıklar da çalışır: `write`, `week`, `catchup`, `install`, `uninstall`, `status`, `--date`, `--dry-run`.

## Kurulum

```bash
./build.sh --install     # ~/.local/bin/bkjournal
bkjournal yaz --kuru     # önce deneyin
bkjournal kur            # her gün otomatik çalışsın (isteğe bağlı)
```

`build.sh` zamanlayıcıyı kendiliğinden kurmaz. Zamanlayıcı ilk çalıştığında macOS, Belgeler klasörüne erişim izni isteyebilir.

## Nota nasıl yazar

- **Yalnızca blok.** Araç, `<!-- bk-journal:start -->` ile `<!-- bk-journal:end -->` arasına sahiptir. Blok varsa yalnızca o değişir; yoksa notun sonuna eklenir. İşlem bayt düzeyinde yapılır: bloğun dışındaki tek bir bayt bile değişmez. Bloğu notta istediğiniz yere taşıyabilirsiniz; bir sonraki çalıştırmada orada güncellenir.
- **Gereksiz yazma yok.** Yeni içerik eskisiyle aynıysa dosyaya dokunulmaz (obsidian-git boş commit üretmez). Blokta zaman damgası yoktur.
- **Atomik yazma.** Aynı klasörde geçici dosyaya yazılır, sonra `rename` ile yerine konur.
- **Yarım işaret.** Başlangıç işareti olup bitiş işareti olmayan nota dokunulmaz, hata verilir.
- **Not yoksa** `.obsidian/daily-notes.json` içindeki şablona bakılır:
  - Şablon yalnızca çekirdek yer tutucuları (`{{date}}`, `{{time}}`, `{{title}}`, `{{date:BİÇİM}}`) içeriyorsa doldurulur ve blok eklenir. Şablonun içine işaretleri koyarsanız blok oraya yerleşir.
  - Şablonda Templater kodu (`<% … %>`) varsa ham kod kopyalanmaz; başlık ve bloktan oluşan sade bir not oluşturulur.
  - Templater'ın "yeni dosyada tetikle" ayarı açık olsa bile sorun çıkmaz: dosya hiçbir zaman boş oluşturulmaz (klasör şablonu uygulanmaz) ve commit başlıklarındaki `<` karakteri `&lt;` olarak yazıldığı için içerikte çalıştırılabilir `<%` kalmaz.
- **Dosya adı ve klasör** her çalıştırmada `.obsidian/daily-notes.json` dosyasından okunur. Desteklenen Moment belirteçleri: `YYYY YY MM M DD D HH H mm m ss s GGGG WW W` ve `[düz metin]`. Çözülemeyen biçimde `YYYY-MM-DD` kullanılır.
- **Proje başlıkları**, `10 Projeler` altında adı eşleşen not ya da klasör varsa ona bağlanır. Eşleşme küçük harfe ve yalnızca harf/rakama indirgenerek yapılır (`trafik360` ↔ `Trafik360`, `biore` ↔ `bio.re`, `isletim-sistemleri` ↔ `İşletim Sistemleri`). Klasörün içinde kendi adını taşıyan not varsa ona, yoksa klasörün içinde oluşturulacak aynı adlı nota (`10 Projeler/Trafik360/Trafik360`) bağlanır.
- **Commit edilmemiş değişiklikler** çalıştırma anının görüntüsüdür: yalnızca bugünün notuna yazılır. Geçmiş bir gün yeniden yazılırken o gün kaydedilmiş bölüm korunur.
- **Haftalık rapor** `<günlük not klasörü>/Haftalık/2026-W47.md` dosyasına aynı işaret kuralıyla yazılır: günlere ve projelere göre toplamlar, proje proje commit başlıkları.

## Ayarlar

`~/Library/Application Support/BKJournal/config.json` (ilk gerçek çalıştırmada varsayılanlarla oluşturulur; eksik alanlar varsayılan değeri alır):

```json
{
  "roots": ["~/Documents/GitHub", "~/IdeaProjects"],
  "vault": "~/Documents/obsidian",
  "extraEmails": ["eski@adres.com"],
  "extraNames": [],
  "projectsFolder": "10 Projeler",
  "weeklyFolder": "",
  "projectMap": { "trafik360-sirlar": "Trafik360", "saloon": "" },
  "scheduleTime": "23:30",
  "maxDepth": 3,
  "skipDirectories": [],
  "excludeRepos": []
}
```

- `projectMap`: depo adı → proje notu. Değer `10 Projeler` altındaki bir adla eşleşiyorsa o kullanılır, aksi halde bağlantı hedefi olarak aynen yazılır; boş değer bağlantıyı kapatır.
- `weeklyFolder`: kasaya göre klasör; boşsa `<günlük not klasörü>/Haftalık`.
- `scheduleTime` değiştiyse `bkjournal kur` yeniden çalıştırılmalıdır.

## Gizlilik ve güvenlik

- Kasadan yalnızca şunlar okunur: `.obsidian/daily-notes.json`, günlük not şablonu, Templater ayar dosyası, proje klasöründeki dosya/klasör **adları** ve yazılacak notun kendisi.
- Depolarda yalnızca salt okunur git komutları çalışır (`log`, `rev-parse`, `status`, `config --get`), `GIT_OPTIONAL_LOCKS=0` ve süre sınırıyla. Ağ erişimi yoktur.
- Yazılan dosyalar: ilgili günlük not(lar), haftalık rapor, veri klasöründeki `config.json` ile `state.json`; `kur` ile `~/Library/LaunchAgents/local.bkjournal.plist` ve `bkjournal.log`.

## Sınırlar

- Günler commit'in **yazar tarihine** göre belirlenir; rebase/amend edilen commit ilk yazıldığı günde kalır.
- Dal adı en iyi tahmindir (commit'e ulaşılan ilk ref; önce `main`/`master`, sonra etkin dal).
- Birleştirme (merge) commit'leri ve stash kayıtları sayılmaz.
- Ay/gün adı içeren tarih biçimleri (`MMMM`, `dddd`) Obsidian'ın diline bağlı olduğu için desteklenmez.
- Bilgisayar kapalıyken kaçan günler bir sonraki çalıştırmada tamamlanır (en fazla 7 gün).

## Geliştirme

```bash
swift build
swift test
swift run bkjournal yaz --kuru
```

Denemelerde gerçek veri klasörü yerine başka bir klasör kullanmak için: `BKJOURNAL_DATA_DIR=/gecici/klasor bkjournal …`
