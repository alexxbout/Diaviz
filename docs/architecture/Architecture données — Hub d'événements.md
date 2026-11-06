# Architecture données — Hub d'événements
>   Source de vérité unique pour Diaviz. Toutes les données (CGM, injections, repas, sport, états, médicaments) vivent dans **un seul magasin SwiftData**. Les analyses (B1, B2, B3, R1, S1…) ne stockent rien : elles **dérivent des vues** depuis des tranches du hub.  

**Statut** : 🟡 En conception (validé le 2026-06-07) · **Techno** : SwiftData (`@Model`) · **Remplace** : structs `Codable` + services mock actuels

---

## Principe directeur
- **Un hub, des dérivations.** Le hub ne contient que des **faits bruts horodatés** (événements). Tout le reste (NightChartData, IOB, charge d'activité, score, tendances) est **calculé à la volée** depuis le hub, jamais persisté en double.
- **Config ≠ événements.** Le profil (DIA, seuils, ratios, dose lente) reste dans `ProfilService`  / `UserDefaults`  . Ce sont des réglages, pas des événements datés.
- **Secrets ≠ hub.** Les tokens OAuth Dexcom vivent dans le **Keychain**, jamais dans SwiftData.
- **Horodatage absolu obligatoire.** Chaque événement porte un `Date`  réel (`2026-06-05 02:14:00`  ). Le temps relatif (« t+42 min après la lente ») est **calculé à l'affichage**, jamais stocké. Sans absolu : impossible de différencier les jours, de trancher une nuit, de calculer TIR/GRI sur 24h, d'aligner injection ↔ glycémie.
---

## 1. Modèle du hub — entités `@Model` 
### `GlucoseReading` — mesure CGM
| Champ | Type | Note |
| ----- | ----- | ----- |
| `id`  | UUID |  |
| `date`  | Date | <p>**horodatage absolu**</p><p> (clé de tri / découpage)</p> |
| `valeur`  | Int | mg/dL |
| `tendance`  | TendanceGlycemie? | enum existant (↑ ↓ →) |
| `tauxVariation`  | Double? | mg/dL/min, fourni par Dexcom si dispo |
| `source`  | SourceDonnee | `.dexcom` / `.healthkit` / `.manuel`  |
>   Refonte de `PointCgm` (aujourd'hui `secondesDepuisRepas` + `valeur`, relatif → orienté mock). Indexer sur `date`.  

### `Injection` — insuline
| Champ | Type | Note |
| ----- | ----- | ----- |
| `id`  | UUID |  |
| `date`  | Date | absolu (ex-`heure`) |
| `type`  | TypeInsuline | `.rapide` / `.lente`  |
| `dose`  | Double | unités |
| `motif`  | MotifInjection? | `.repas` / `.correction` / `.basale` — **trigger B3 = rapide **`******.correction******`** au coucher** |
| `glycemieAuMoment`  | Int? |  |
| `repasAssocieId`  | UUID? | lien vers `Repas`  |
| `zoneInjection`, `coteInjection`, `note`  |  | existant |
| `source`  | SourceDonnee |  |
### `Repas` + `Aliment` 
| `Repas`  | Type |  | `Aliment`  | Type |
| ----- | ----- | ----- | ----- | ----- |
| `id`  | UUID |  | `id`  | UUID |
| `date`  | Date |  | `emoji`, `nom`  | String |
| `aliments`  | [Aliment] | relation | `quantite`  | Double |
| `glucidesTotaux`  | Double | calc | `glucides`  | Double |
| `iobAuDebut`  | Double? |  | `insuline`  | Double |
| `etatAnalyse`  | EtatAnalyse |  |  |  |
### `ActiviteSportive` 
| Champ | Type | Note |
| ----- | ----- | ----- |
| `id`  | UUID |  |
| `dateDebut`  | Date | absolu |
| `dureeMinutes`  | Int |  |
| `type`  | TypeSport |  |
| `intensite`  | Intensite |  |
| `glucidesPreSport`  | Double? |  |
| `iobAuDebut`  | Double? |  |
| `healthKitData`  | HealthKitWorkoutData? | snapshot |
| `source`  | SourceDonnee | `.healthkit` / `.manuel`  |
### `EtatDeclare` — **nouveau** (cible E1)
| Champ | Type | Note |
| ----- | ----- | ----- |
| `id`  | UUID |  |
| `date`  | Date |  |
| `type`  | TypeEtat | `.stress` / `.maladie` / `.manqueSommeil` / `.cycle` / `.alcool` / `.autre`  |
| `intensite`  | Int? | échelle subjective |
| `note`  | String? |  |
### `Medicament` — **nouveau** (cible M1)
| Champ | Type | Note |
| ----- | ----- | ----- |
| `id`  | UUID |  |
| `date`  | Date |  |
| `nom`  | String | corticoïdes, etc. |
| `dose`  | String? |  |
| `recurrent`  | Bool | traitement de fond vs ponctuel |
| `note`  | String? |  |
### `PeriodePause` — **nouveau** (mode pause)
| Champ | Type | Note |
| ----- | ----- | ----- |
| `id`  | UUID |  |
| `debut`  | Date |  |
| `fin`  | Date? | null = pause en cours |
| `motif`  | MotifPause | `.voyage` / `.maladie` / `.corticoides` / `.autre`  |
| `note`  | String? |  |
>   Les analyses **excluent** tout événement dont la `date` tombe dans une `PeriodePause`. Données conservées, juste écartées du calcul.  

### Énumération transverse
`SourceDonnee` = `.dexcom` / `.healthkit` / `.manuel` — sur chaque entité ingérable, pour tracer la provenance et arbitrer les doublons (ex : CGM Dexcom vs HealthKit).

---

## 2. Config (hors hub) — `ProfilService` / UserDefaults
Reste tel quel, lu par toutes les analyses :

- `ProfilUtilisateur.dureeActionInsulineHeures`  → **DIA** (base du calcul IOB)
- `SeuilsGlycemiques`  → hypo / hyper (défaut 70 / 180)
- `RatiosParMoment`  / `ratioUnique`  / `ratioCorrection`  
- `insulineRapide`  / `insulineLente`  **À ajouter** (réglages d'analyse) :
- `seuilCoucherAnalyse`  (B2, défaut ≈ 160 mg/dL, distinct du seuil hyper)
- politique de fenêtrage « depuis le dernier changement de dose de lente » (B2/B3)
---

## 3. Flux de données

- **Écriture** : seuls l'ingestion (Dexcom/HealthKit) et la saisie manuelle écrivent dans le hub.
- **Lecture** : les vues dérivées et les analyses lisent des **tranches** (par date/nuit/fenêtre).
- `NightChartData`  = **vue dérivée**, calculée depuis une tranche nuit, **jamais stockée**.
---

## 4. Matrice qui-écrit / qui-lit
### Écrivains
| Producteur | Entités écrites |
| ----- | ----- |
| Ingestion Dexcom | `GlucoseReading` (.dexcom) |
| Ingestion HealthKit | `ActiviteSportive` (.healthkit) ; CGM HealthKit éventuel |
| Saisie manuelle | `Injection`, `Repas`, `ActiviteSportive`, `EtatDeclare`, `Medicament`, `PeriodePause`, `GlucoseReading` (.manuel) |
### Lecteurs (analyses → tranches consommées)
| Analyse | Tranches du hub | Vues dérivées | Config |
| ----- | ----- | ----- | ----- |
| <p>**IOB service**</p><p> (transverse)</p> | `Injection` (.rapide) récentes | — | DIA |
| **Score quotidien** | `GlucoseReading` 24h | TIR / GRI | seuils |
| **B1 — basale** | `GlucoseReading` nuit · `Injection` lente/rapide · `ActiviteSportive`  | NightChartData (zones, pente z3) | seuils |
| **B2 — endormissement** | tranche B1 | NightChartData · IOB · ChargeActivité | seuils · seuilCoucherAnalyse · fenêtrage dose |
| **B3 — corrections** | tranche B2 · `Injection` rapide `.correction` (trigger) · `Repas` (temps depuis repas) | NightChartData · IOB · ChargeActivité | idem B2 |
| **R1 — repas/insuline** | `Repas` · `Injection` rapide · `GlucoseReading`  | — | ratios |
| **S1 — sport** | `ActiviteSportive` · `GlucoseReading`  | ChargeActivité | — |
| **E1 — état** | `EtatDeclare` · `GlucoseReading`  | — | — |
| **M1 — médicaments** | `Medicament` · `GlucoseReading`  | — | — |
>   **Dose lente courante + historique des changements** = dérivé de `Injection(type: .lente)` trié par date. Pas d'entité dédiée.
Toutes les analyses filtrent d'abord les événements en `PeriodePause`.  

---

## 5. Impact migration (depuis l'état mock actuel)
- `PointCgm`  (relatif) → `GlucoseReading`  (absolu). Refonte, pas un simple rename.
- 13 services `*ServiceMock`  → services réels lisant le hub, migrés **un par un**.
- `ProfilService`  et `AlimentsRecentsService`  (déjà UserDefaults) : **inchangés**.
- Modèles transverses existants réutilisés tels quels : `ChargeActivite`  (remplacé le 2026-09-23 par `NiveauChargeActive`, voir Charge active), `TendanceGlycemie`  , `SportResume`  .
- **Tout modélisé dès maintenant** (y compris `EtatDeclare`  , `Medicament`  , `PeriodePause`  ) pour éviter les migrations de schéma SwiftData ultérieures, même si E1/M1/pause ne sont pas encore implémentés côté UI.
---

## Décisions actées (2026-06-07)
- ✅ Persistance = **SwiftData** .
- ✅ Hub central unique, analyses dérivent des vues (pas de stockage redondant).
- ✅ Horodatage absolu partout.
- ✅ Toutes les entités modélisées maintenant (dont états / médocs / pause).
- ✅ Dexcom : **sandbox d'abord**, bascule prod ensuite.
- ⏳ Reste à cadrer : doc Dexcom OAuth (Vercel + Keychain + endpoints EGV), courbe de décroissance IOB (V1 simple).
