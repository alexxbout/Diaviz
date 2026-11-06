# Assembleur Score quotidien (GRI)
>   Dérivation du score de gestion glycémique (0–100) depuis les `GlucoseReading` du hub. **Observation factuelle**, jamais un conseil. Diaviz n'est pas un dispositif médical.  

**Statut** : 🟡 À implémenter (2026-06-20) · **Remplace** : `ScoreJournalierServiceMock` · **Voir** : « Modèle IOB » (même couche dérivation)

---

## 1. Formule (GRI — Klonoff 2022)
Bandes glycémiques (mg/dL) et coefficients :

```
%TBR2  = % temps < 54          × 3.0
%TBR1  = % temps 54–69         × 2.4
%TIR   = % temps 70–180        (in range, hors GRI)
%TAR1  = % temps 181–250       × 0.8
%TAR2  = % temps > 250         × 1.6

GRI    = 3.0·%TBR2 + 2.4·%TBR1 + 1.6·%TAR2 + 0.8·%TAR1
Score  = max(0, min(100, 100 − GRI))
```
Les pourcentages = fraction des **échantillons CGM** de la fenêtre dans chaque bande (échantillons Dexcom ≈ 1 / 5 min, supposés équi-espacés).

---

## 2. Conventions
- **Jour métabolique 06h → 06h** (helper existant `debutJourMetabolique`  ). La nuit 00h–06h appartient à la journée précédente. Fenêtre d'un jour `J`  = `[06h(J), 06h(J+1)]`  .
- **Couverture CGM** : `nbÉchantillons / nbAttendus`  (288 sur 24h à 5 min). Si **< 70 %** → score **indisponible** (`nil`  ), pas de faux score (dégradation gracieuse). Le **jour en cours** est forcément partiel (différé Dexcom ~3 h) → couverture calculée sur le temps écoulé, pas sur 24h.
- **Hypos** : `hypoCount`  = nombre d'**épisodes** distincts < 70 (séparés par un retour ≥ 70 entre deux). `severeHypoCount`  = épisodes passant < 54.
- **Pic** : `peakValue`  = max glycémie de la fenêtre ; `peakTime`  = son heure (`HH:mm`  ).
- **mealContext / sportContext** : `nil`  en V1 (narratif = couche LLM, plus tard).
---

## 3. Sortie — `FaitsJour` 
Le calcul produit le `FaitsJour` déjà consommé par l'UI (`NarrationJourVue.swift`) :

| Champ | Source |
| ----- | ----- |
| `score`  | `100 − GRI`  |
| `tir`  | %TIR |
| `tbrLevel1` / `tbrLevel2`  | %TBR1 / %TBR2 |
| `tarLevel1` / `tarLevel2`  | %TAR1 / %TAR2 |
| `hypoCount` / `severeHypoCount`  | épisodes |
| `peakTime` / `peakValue`  | pic |
| `mealContext` / `sportContext`  | `nil` (V1) |
---

## 4. Architecture & contrat d'API
### `CalculScoreJournalier` (pur, `services/derivation/`)
`Sendable`, `nonisolated` (réutilisable hors `MainActor`). Aucune dépendance au hub.

```
static func faits(depuis lectures: [GlucoseReading],
                  fenetre: ClosedRange<Date>,
                  couvertureMin: Double = 0.70) -> FaitsJour?
```
Retourne `nil` si couverture < `couvertureMin`. `lectures` = échantillons de la fenêtre.

### `ScoreService` (hub, `services/hub/`, `@Observable @MainActor`)
Remplace `ScoreJournalierServiceMock` en **conservant son API publique** (les vues n'en consomment que ça) :

```
func demarrer(contexte: ModelContext)
func score(pour jour: Date) -> ScoreJournalier?
func historiqueSept(jusquA jour: Date) -> [(jour: Date, score: Int?)]
var  joursNavigables: [Date]               // 30 derniers jours avec couverture suffisante
var  heuresDataDuJour: Double               // depuis 06h, borné [0,24]
var  scoreDuJour: Int                        // score partiel du jour courant (0 si indispo)
var  partielDuJour: ScoreJournalier
static func debutJourMetabolique(pour date: Date) -> Date   // inchangé
```
Implémentation : pour un jour, fetch les `GlucoseReading` de la fenêtre métabolique, appelle `CalculScoreJournalier.faits(...)`, emballe en `ScoreJournalier`. Historique = boucle sur les jours (volume trivial, recalcul à la volée acceptable en V1 ; cache possible plus tard).

---

## 5. Branchements UI (inchangés en signature)
- `**AccueilVue**`  — carte score (`CarteScoreQuotidien`  / `contenuScore`  ) : `scoreDuJour`  , `historiqueSept`  , `heuresDataDuJour`  . Pattern identique à l'IOB : `@State service`  , `@Environment(\.modelContext)`  , `.task { demarrer }`  + `.onAppear`  pour rafraîchir.
- `**DetailScoreVue**`  — détail + navigation 30 j : `score(pour:)`  , `joursNavigables`  , `partielDuJour`  .
- Purge du mock → données de démo en `#if DEBUG`  (container in-memory peuplé de `GlucoseReading`  ).
---

## 6. Découpage du travail
⚠️ **Couplage** : `ScoreService` est central — les deux vues en dépendent. La parallélisation se fait donc **après** le socle :

1. **Socle (séquentiel, d'abord)** : `CalculScoreJournalier`  + `ScoreService`  (API §4 complète) + purge mock. Build vert, commit.
2. **Parallèle (2 worktrees)** sur le socle mergé, fichiers disjoints :
    - **Lot A** : branchement **AccueilVue** (carte score réelle) + previews.
    - **Lot B** : branchement **DetailScoreVue** (détail + navigation 30 j) + previews.

---

## 7. Décisions actées (2026-06-20)
- ✅ Jour métabolique 06h→06h · couverture min 70 % · score `nil`  si insuffisant.
- ✅ Hypos = épisodes (pas %temps) · pic = max de la fenêtre.
- ✅ Calcul pur séparé du service (testable, réutilisable ML).
- ✅ API publique du service identique au mock → vues inchangées en signature.
- ✅ Score = observation, jamais un conseil (formulation factuelle).
## 8. Affichage — jour en cours vs dernier jour complet
Problème : à cause du **différé Dexcom (~3 h)**, le jour métabolique en cours (depuis 06h) n'a quasiment **aucune donnée avant ~9h** du matin, et peu ensuite. Le score partiel matinal n'est donc pas représentatif (souvent **0 → « Très difficile »**, faux signal démotivant).

Règle de bascule (carte d'accueil « Score du jour » + page détail) :

- Le jour en cours est dit **significatif** s'il a **≥ 6h de données CGM réelles** (compte des échantillons × 5 min, PAS les heures écoulées depuis 06h). Seuil ajustable.
- **Significatif** → la carte montre le jour en cours (partiel) : titre « Score du jour », sous-texte « Xh de données », 7ᵉ barre rendue « en cours ».
- **Pas significatif** (le matin) → la carte **bascule sur le dernier jour consolidé** : titre « Dernier score », sous-texte = date (« Hier »), toutes les barres consolidées. Jamais de 0 trompeur.Implémentation (`ScoreService`  ) : `heuresDonneesJourCourant`  , `jourCourantSignificatif`  (≥ 6h), `jourAffiche`  (jour en cours si significatif sinon `joursNavigables.last`  ), `scoreAffiche`  , `scoreDuJourSignificatif`  . `ContenuCarteScore`  porte un flag `estEnCours`  .
Page détail : pour le jour en cours **non significatif**, le cercle et la barre affichent **« — »** (pas un faux 0). Sheet du matin : montre le **dernier jour consolidé** (`joursNavigables.last` ), pas le jour en cours.
