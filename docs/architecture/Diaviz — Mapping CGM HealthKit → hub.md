# Ingestion CGM — HealthKit (source primaire)
>   Comment les glycémies Dexcom arrivent dans le hub `GlucoseReading` de Diaviz. Voir le diagramme sur ce canvas.  

**Statut** : ✅ Implémenté (`main`) · **Source** : Apple Santé (HealthKit) · **Remplace** : l'intégration API Dexcom OAuth (archivée sur la branche `feature/dexcom-api`)

---

## POURQUOI
- Diaviz a besoin des glycémies CGM en continu pour le **score quotidien** et les analyses (**B1** basale, **B2** endormissement, **B3** corrections).
- **Pas de temps réel possible** : Dexcom n'expose aux tiers (son API **et** Apple Santé) qu'avec **~3 h de retard en Europe**. Le temps réel reste cantonné à l'app Dexcom. Diaviz est donc, par conception, **rétrospectif**.
- **HealthKit choisi comme source unique** plutôt que l'API Dexcom : mêmes données (valeur + tendance + taux de variation) **sans OAuth, sans proxy Vercel, sans rate-limit**, avec **réveil en arrière-plan natif**. L'API Dexcom (OAuth) avait le **même retard de 3 h** → redondante, archivée sur `feature/dexcom-api`  .
---

## QUOI
- **Donnée** : échantillons `HKQuantitySample`  de type `bloodGlucose`  écrits par l'app **Dexcom ONE+** dans Apple Santé.
- **Cadence de la donnée** : 1 mesure / **5 min** (288/jour), disponibles **3 h après** la mesure réelle.
- **Fréquence de récupération côté Diaviz** :
    - **Au lancement de l'app** (`.task`  racine) → une synchro incrémentale.
    - **En continu** via `HKObserverQuery`  + `enableBackgroundDelivery(frequency: .hourly)`  → iOS réveille l'app à l'arrivée de nouvelles données (best-effort, cadence ~horaire).

- **Événements déclencheurs (triggers)** :
    - Ouverture/lancement de l'app → `synchroniser()`  .
    - Nouvel échantillon dans Santé (premier plan **ou** arrière-plan) → callback `HKObserverQuery`  → `synchroniser()`  .

- **Volume & rétention** : ~quelques Mo/an, **tout local** (SwiftData). Conservé indéfiniment, pas de purge.
- **Pas de backfill profond** : le 1er pull est borné à **7 jours**. Les analyses corrèlent CGM ↔ **événements Diaviz** (lente, corrections, repas, sport) ; sans events loggés, remonter loin n'a pas d'intérêt (seul le score se déduit du CGM seul).
- **Conséquence produit** : la glycémie « à l'instant T » (repas, sport, hypo) n'est pas disponible en live → **saisie manuelle** quand c'est nécessaire.
---

---

## COMMENT
- **Autorisation** : `requestAuthorization`  en lecture `bloodGlucose`  , demandée au lancement. Entitlement `com.apple.developer.healthkit`  + clé `NSHealthShareUsageDescription`  . _(HealthKit ne fonctionne que sur iPhone réel, pas le simulateur.)_
- **Lecture incrémentale** : `HKAnchoredObjectQueryDescriptor`  avec une **ancre** `**HKQueryAnchor**`  **persistée** (UserDefaults) → ne relit jamais l'existant ; 1er pull borné à 7 j.
- **Arrière-plan** : `HKObserverQuery`  longue durée + `enableBackgroundDelivery(.hourly)`  .
- **Idempotence** : déduplication sur l'**horodatage** (`date`  en `@Attribute(.unique)`  ) + vérification des dates déjà présentes avant insertion.
- **Le hub ne stocke que des faits bruts** ; les analyses **dérivent des vues à la demande** (rien de calculé n'est persisté en double).
### Mapping des champs (HealthKit → `GlucoseReading`)
| Champ HealthKit | → `GlucoseReading`  | Note |
| ----- | ----- | ----- |
| `HKQuantitySample.startDate` (UTC) | `date`  | horodatage absolu, clé de tri / dédup |
| `quantity` (mg/dL) | `valeur` (Int) | arrondi |
| `metadata["Trend Arrow"]`  | `tendance` (`TendanceGlycemie?`) | `Flat`, `SingleUp`, `FortyFiveUp`, `DoubleUp`, `SingleDown`, `FortyFiveDown`, `DoubleDown` → 5 états ; recalculable depuis la série sinon |
| `metadata["Trend Rate"]`  | `tauxVariation` (Double?) | ≈ dixièmes de mg/dL/min (à confirmer) ; bonus d'affichage, non requis par les analyses |
| `sourceRevision.source.name` = `Dexcom ONE+`  | `source` = `.healthkit`  | provenance |
