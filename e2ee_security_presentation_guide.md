# NASIIB HOSPITAL - WARBIXIN CAAFIMAAD & AMMAANKA XOGTA (E2EE)
**Hanuuniyaha Sharaxaada Tiknoolajiyada End-to-End Encryption (E2EE) ee App-ka Nasiib Hospital**

---

## 1. Hordhac
Wada-sheekaysiga u dhexeeya Bukaanka iyo Dhaqtarka ee ka dhex dhaca App-ka Nasiib Hospital waxaa lagu ilaaliyaa tignoolajiyada ugu casrisan ee ammaanka xogta ee loo yaqaan **End-to-End Encryption (E2EE)**. Tani waxay xaqiijinaysaa in xogta bukaanku ay tahay mid qarsoodi ah oo aysan cid kale akhrin karin.

---

## 2. Waa Maxay End-to-End Encryption (E2EE)?
E2EE waa habka codaynta xogta (Encryption) halkaas oo **kaliya** dadka wada sheekaysanaya (Bukaanka iyo Dhaqtarka) ay awood u leeyihiin inay akhriyaan fariimaha.

* **Ka hor intaan la dirin**: Fariinta waxaa lagu coddeeyaa (encrypt) moobilka bukaanka.
* **Inta ay wadada ku jirto (Database)**: Fariintu waxay noqotaa xuruuf qasan oo aan la fahmi karin.
* **Marka ay gaarto dhaqtarka**: App-ka dhaqtarka ayaa si automatic ah u furaya (decrypt) fariinta.

---

## 3. Tusaale Wax-Ku-Ool Ah (How it Works)

Aynu soo qaadanno Bukaanka oo soo diraya fariinta ah:  
> **"Assalamu alaikum dhakhtar, waxaan dareemayaa xanuun dhanka ilkaha ah."**

Hoos ka eeg sida ay fariintaasi u kala beddelmayso marxaladaha kala duwan:

| Marxaladda | Meesha ay ku dhex jirto | Sida ay u muuqato fariintu | Cidda akhrin karta |
| :--- | :--- | :--- | :--- |
| **1. Dirista** | Moobilka Bukaanka (Sender) | `"Assalamu alaikum dhakhtar..."` | **Bukaanka** (Waa la akhrin karaa) |
| **2. Kaydinta** | Supabase Database (Server) | `U2FsdGVkX19zS0F0cDZxTzB1SDRwZz09` | **Cisna** (Waa xuruuf qarsoon/qasan) |
| **3. Qaabilaadda** | Web Dashboard-ka Dhaqtarka (Receiver) | `"Assalamu alaikum dhakhtar..."` | **Dhaqtarka** (Waa la akhrin karaa) |

---

## 4. Waa Maxay Faa'iidooyinka Loo Sameeyay E2EE?

1. **Ilaalinta Qarsoodiga (Privacy)**: Xitaa Shirkadda Supabase, Maamulayaasha Database-ka (Database Administrators), ama dadka Internet-ka bixiya (ISPs) ma akhrin karaan wada-sheekaysiga caafimaad ee Bukaanka iyo Dhaqtarka.
2. **U-hoggaansanaanta Shuruucda Caafimaadka (HIPAA Compliance)**: Shuruucda caafimaadka caalamiga ah waxay u baahan yihiin in xogta bukaanada la qariyo marka la kaydinayo ama la dirayo. E2EE waxay buuxinaysaa shuruudaas.
3. **Ka-hortagga Jabsashada (Anti-Hacking)**: Haddii ay dhacdo in database-ka isbitaalka la jabsado (Data Breach), hackers-ku ma helayaan wax wada-sheekaysi ah oo ay akhrin karaan, sababtoo ah dhammaan fariimaha waxay u yaalaan sidii xuruuf qasan.

---

## 5. Su'aalaha Badanaa La Weydiiyo (FAQ)

### S: Haddii aan database-ka Supabase ka tirtiro fariin, ma ka tirtirmaysaa meel kasta?
J: Haa, haddii fariinta laga tirtiro database-ka Supabase, waxay ka baxaysaa app-ka bukaanka iyo kan adminka si joogto ah.

### S: Sidee lagu ogaanayaa in wada-sheekaysigu uu yahay mid ammaan ah?
J: Shaashada wada-sheekaysiga ee Bukaanka iyo Dhaqtarka waxaa ku yaala calaamad quful cagaaran ah iyo qoraal leh: **`🔒 End-to-End Encrypted`**, taas oo xaqiijinaysa in adeeggan uu shidan yahay.

---
*Nasiib Hospital - Mar kasta Ammaankaaga iyo Caafimaadkaaga ayaa noogu horreeya.*
