FS25 KONTRAT YÖNETİCİSİ - v1.14.0.0
===============================================================================

Bu sürüm, FS25_ContractGuard modunun tamamını yeni Kontrat Yöneticisi çatısı
altında taşır ve üstüne kural motoru ile oyun içi ayar sekmesini ekler.

OYUN İÇİ ARAYÜZ (oyunun kendi ekranları)
- ESC > Ayarlar > "Kontrat Yöneticisi" alt sekmesi: tüm kurallar oyunun stok
  aç/kapa ve çoklu seçenek kontrolleriyle düzenlenir. Yalnızca sunucu
  yöneticisi değiştirebilir; diğer oyuncular yalnızca "Çiftliğinizin
  istatistiği" bölümünü görür (tamamlanan/başarısız/iptal/süre aşımı,
  toplam kazanç ve ceza, son 5 kontrat).
- ESC > Kontratlar: seçili kontratın detay listesine üç satır eklenir:
  kalan süre, olası başarısızlık cezası, çiftliğin aktif kontratı / limit.
- Ayar değişiklikleri anında tüm oyunculara yayılır ve bir sonraki oyun
  kaydında diske yazılır.

KURULUM
1. FS25_ContractManager.zip dosyasını sunucunun mods klasörüne yükleyin.
2. FS25_ContractGuard.zip dosyasını mods klasöründen KALDIRIN. İkisi birlikte
   yüklenirse Kontrat Yöneticisi kendi koruma katmanını kapatır ve log.txt'ye
   hata yazar.
3. Modu kayıt için etkinleştirin ve sunucuyu yeniden başlatın.
4. Bağlanan bütün PC/Mac oyuncularında aynı mod sürümü bulunmalıdır.

KAYIT VERİSİ DEVRALMA
Kayıt klasöründe eski FS25_ContractGuard.xml varsa ilk yüklemede otomatik
okunur; ilk kayıtta FS25_ContractManager.xml olarak yeniden yazılır. Aktif
kontratların korunan ürün miktarı (baseline) kaybolmaz.

KORUMA KURALLARI
- Kontrat ürünü aynı çiftliğe ait biçerdöver, römork, kamyon ve aktarma
  araçları arasında taşınabilir.
- Yere dökme engellenir.
- Başka çiftliğe ait araca aktarma engellenir.
- Çiftlik silosu, fabrika, bunker ve yanlış satış noktasına boşaltma
  engellenir.
- Yalnızca kontratta gösterilen teslim noktası ürünü kabul eder.
- Hasat veya teslimat başladıktan sonra kontrat iptal edilemez.
- Kontrat süre aşımı ya da başka zorunlu sebeple başarısız olursa,
  kontrat kabulünden sonra çiftliğin araçlarında/balyalarında oluşan net
  ürün miktarı geri alınır.

AYAR DOSYASI
Documents\My Games\FarmingSimulator2025\modSettings\FS25_ContractManager.xml
İlk çalıştırmada varsayılanlarla oluşturulur. Geçersiz değerler varsayılana
çekilir ve log.txt'ye yazılır. Alanlar:
  guard#enabled / confiscateOnFail / blockCancelAfterProgress
  reward#multiplier (1.25)  ödül çarpanı; #min / #max taban-tavan (0 = yok)
  reward#failPenaltyPercent (10)  başarısız/iptal/süre aşımında ödülün yüzdesi ceza
  reward#leaseCostMultiplier (1.0)  kiralık makine maliyeti çarpanı
  limits#maxActivePerFarm (3)  çiftlik başına aynı anda aktif kontrat (0 = sınırsız)
  generation#maxTotal (0 = oyun varsayılanı, en çok 80)  panodaki toplam kontrat
  generation#maxPerType (0 = oyun varsayılanı)  tür başına üst sınır
  generation#refreshMultiplier (1.0)  yeni kontrat üretim aralığı çarpanı
  duration#multiplier (1.0)  yeni üretilen kontratların süresi
  duration#warnAtMinutes ("60,15")  bitişe kalan oyun dakikası eşiklerinde uyarı
  types/type#name #enabled #weight  kontrat türü aç/kapat ve göreli ağırlık
  compat#overrideBetterContracts (false)  aşağıya bakın

BETTERCONTRACTS İLE BİRLİKTE
FS25_BetterContracts da yüklüyse ödül, ceza, limit, üretim ve süre kuralları
otomatik olarak geri çekilir (iki mod aynı noktalara yazar, çarpanlar
katlanırdı). Koruma (Guard) ve kontrat geçmişi çalışmaya devam eder.
compat#overrideBetterContracts="true" yaparsanız bu modun kuralları
BetterContracts'ın üstüne uygulanır; bunu yalnızca bilinçli yapın.

KONTRAT GEÇMİŞİ
Sunucu, kabul edilen / biten kontratları ve çiftlik başına istatistiği
kayıt klasöründeki FS25_ContractManager.xml içinde tutar (son 200 kontrat).
Oyun içi görüntüleme sonraki sürümde.

İTİBAR VE SIRALAMA (1.1)
- Tamamlanan kontrat çiftliğe puan kazandırır; başarısız, iptal ve süre aşımı
  puan düşürür (Ayarlar > Kontrat Yöneticisi > İtibar).
- Puan arttıkça ödül bonusu (en yüksek puanda %25) ve eşik üstünde +1 aktif
  kontrat hakkı. Yönetici iptali puan düşürmez.
- Ayar sekmesindeki istatistik bölümünde tüm çiftliklerin sıralaması görünür.
- Tarla bekleme süresi: kontratı biten tarla, ayarlanan oyun saati kadar yeni
  kontrat almaz (Üretim > Tarla bekleme süresi; 0 = kapalı).

KONTRAT REZERVASYONU (1.2)
- Kontratlar sayfasında kabul edilmemiş bir kontrat seçip alt çubuktaki
  "Rezerve et" ile çiftliğiniz adına ayarlanan dakika kadar rezerve edin;
  o sürede başka çiftlik alamaz. Çiftlik başına tek rezervasyon.
- Kabul edince, süre dolunca ya da "Rezervasyonu bırak" ile kalkar.

KONTRAT YÖNETİMİ SAYFASI (1.8)
- ESC menüsünde kendi sekmesi; kenar çubuğunda oyunun Kontratlar sayfasının hemen
  altında durur. Üç filtre: Aktif, Yeni, Geçmiş.
- Listeden bir kontrat seçin; altında detayı ve yapabileceğiniz işlemler
  buton olarak çıkar: rezerve et/bırak, ortağa davet et, ortaklığı kabul et,
  ortaklıktan ayrıl, devret, zorla iptal, çiftliğe ata, panoyu yenile.
- Hedef çiftlik gerektiren işlemlerde "Hedef çiftlik" satırındaki seçiciyi
  (oyunun kendi ok tuşlu kontrolü) kullanarak çiftliği seçin.
- Yönetici olmayan oyuncular yalnızca kendi kontratlarını ve kendilerine açık
  işlemleri görür. Konsol komutları da çalışmaya devam eder.

ORTAKLIK KONTRATLAR SAYFASINDA + ARAYÜZ ANAHTARI (1.11)
- Kontratlar sayfasında kendi çalışan kontratınızı seçince "Davet et: <çiftlik>"
  ve "Sonraki çiftlik" butonları çıkar. Sonraki çiftlik ile hedefi değiştirin,
  Davet et ile gönderin. Kontrat Yönetimi sayfası bunun için şart değil.
- Davet edilen ya da ortak olan çiftlik, kontratı kendi Aktif listesinde görür;
  kabul/reddet/ayrıl butonları oradadır. Sahip olmadığı kontratta oyunun İptal
  butonu gösterilmez.
- Ayarlar > Arayüz > "Menüde Kontrat Yönetimi sayfası": kenar çubuğundaki sekmeyi
  anında gizler/gösterir. Ortaklık sistemi ise Ayarlar > Ortak kontrat > açık/kapalı.

ORTAK KONTRAT - ÇİFTLİK BAŞINA KAYIT (1.9)
- Ortak kontratta "Ortaklık" bölümü, katılan her çiftliği kendi satırında gösterir:
  rolü (sahip/ortak), teslim ettiği litre, payı ve o ana kadarki hak edişi.
  Katkı henüz ölçülmediyse "eşit bölüşüm" yazar.
- Bekleyen davetler de burada görünür: hangi çiftlik, kaç dakika sonra düşecek.
- Davet edilen çiftlik "Ortaklığı kabul et" ya da "Daveti reddet" seçebilir.
- Geri alınamayan işlemler (davet, devir, zorla iptal, çiftliğe ata, panoyu yenile,
  ortaklıktan ayrıl) çalışmadan önce oyunun kendi onay penceresini açar.
  Pencere açılamazsa satır soruya döner ve ikinci basış uygular; hedef çiftliği
  değiştirirseniz ya da başka kontrat seçerseniz o onay düşer.

ORTAK KONTRAT (1.7)
- Kontratı alan çiftlik başka bir çiftliği ortak edebilir: konsolda
  cmInvitePartner <kontratNo> <çiftlikNo>. Davet edilen oyuncu bildirim alır ve
  Kontratlar sayfasındaki "Ortaklığı kabul et" ile katılır.
- Ödül katkıya göre bölünür: teslim edilen litre ve tarlada çalışılan süre
  ölçülür. Katkı yoksa eşit bölünür. Zarar da aynı oranda paylaşılır.
- Ortak çiftlik kontrat ürününü taşıyabilir ve tarlada çalışabilir; koruma
  ortağı kendi çiftliği gibi görür.
- Aktif kontrat limiti ve kota yalnızca sahibe işler; itibar ortağa yarım yazılır.
- Ayarlar > Ortak kontrat: açık/kapalı, en fazla ortak, davet süresi.

ZİNCİR VE NPC (1.6)
- Kontrat zinciri: aynı tarlada hazırlık, ekim, bakım, hasat sırasını takip eden
  çiftlik sonraki adımda ek ödül alır (Ayarlar > Zincir ve NPC).
- NPC ilişkisi: aynı tarla sahibinin işlerini yapan çiftlik o kişiden daha iyi
  ödül alır; her tamamlanan iş bonusu artırır.
- Kısmi ödeme: başarısız kontratta tamamlanan orana göre ödemenin bir kısmı
  yapılabilir (Ayarlar > Ödül ve ceza).
- Kademeli ceza: üst üste başarısızlıkta ceza yüzdesi artar, başarıyla sıfırlanır.
- Kontrat kotası: çiftlik başına günlük ve aylık kabul limiti (Ayarlar > Limitler).

KİRALIK MAKİNE (1.5)
- Ayarlar > Kiralık makine: kontratla makine kiralama tamamen kapatılabilir ya
  da itibar eşiğine bağlanabilir. İzin yoksa kontrat makinesiz başlar ve
  çiftliğe bildirim gider.

UZAKLIK VE ZORLUK (1.4)
- Uzaklık bonusu: kontrat tarlası çiftlik merkezinden (çiftlik evi, yoksa
  arazilerin ortası) uzaklaştıkça km başına yüzde, üst sınırlı.
- Küçük tarla bonusu: referans alanın altındaki tarlalar küçüldükçe daha çok
  kazandırır.
- Tür zorluğu bonusu: taş toplama, ölü ağaç, ağaç taşıma, kaya, ot, çapa,
  sarma ve sürme kontratlarına sabit ek yüzde.
  Üçü de Ayarlar > Uzaklık ve zorluk; varsayılan kapalı. Detayda satır olarak
  görünür.

HARİTA İŞARETLERİ (1.3)
- Çiftliğinizin rezerve ettiği kontratın tarlası haritada işaretlenir; isterseniz
  panodaki tüm açık kontratlar da (Ayarlar > Harita). Oyunun kendi işaretleri.

ZAMANLI BONUSLAR (1.3, gerçek saat)
- Hafta sonu ve mutlu saat bonusu ödüle eklenir (Ayarlar > Zamanlı bonuslar).
  Varsayılan kapalı. Kontrat detayında "Etkinlik bonusu" satırı görünür.

YÖNETİCİ ARAÇLARI (sunucu yöneticisi)
- ESC > Kontratlar sayfasının alt çubuğunda "Panoyu yenile": kabul edilmemiş
  tüm kontratlar silinir ve yenileri üretilir.
- Seçili aktif kontratta "Zorla iptal": koruma engeli aşılır, para cezası
  uygulanmaz, biriken kontrat ürünü yine geri alınır.
- Konsol (~): cmListContracts, cmRefreshContracts, cmCancelContract <id>,
  cmAssignContract <id> <çiftlikNo>, cmTransferContract <id> <çiftlikNo>
  (aktif kontratı devret; kiralık makineli kontrat devredilmez). Hepsi sunucuda
  yetki doğrulamasından geçer; web panelinden de yapılabilir.

WEB PANELİ (Discord Bridge panosu)
Köprü panosunun Kontratlar sekmesinde "Kontrat kuralları" kartı bulunur:
yönetici rolü tüm kuralları ve kontrat türlerini oradan değiştirebilir,
kontratı zorla iptal edebilir ve panoyu yenileyebilir. Değişiklik komut
dosyasıyla sunucuya ulaşır, sunucu uygular ve sonucu geri bildirir.

DISCORD BRIDGE
FS25_DiscordBridge modu da yüklüyse kontrat kabul/bitiş/ödeme, süre uyarısı,
koruma engelleri ve kural değişiklikleri Discord'a gider. Ayarlar sekmesindeki
"Entegrasyonlar > Discord Bridge olayları" ile kapatılabilir. Köprü yoksa
hiçbir şey olmaz.

SORUN BİLDİRİMİ
İletişim: hello@kahrastudio.art · Kaynak kod: https://github.com/Dostlar-Studio/FS25_ContractManager
log.txt içinde "[CM]" geçen satırları gönderin. Oyunun kendi kontrat kodunda
bir hata yakalanırsa "[CM] Game field-completion code failed" satırı yazılır
ve oyun kapanmaz; bu satırı da ekleyin.

ÖNEMLİ
Oyun, aynı türdeki normal ürün ile kontrat ürününü ayrı ayrı etiketlemez.
Bu nedenle aktif kontrat varken aynı ürün türünü kendi silonuzdan araçlara
yüklemeyin. Kurulumdan önce kayıt dosyanızın yedeğini alın.

Bu bir script modudur; konsollarda çalışmaz.
