# Sport — Branchements réels (import Health + courbe glycémique)
>   Le domaine sport est **déjà branché en réel** à ~90 % (modèle SwiftData, saisie manuelle, service hub, couture analyses). Il ne reste que **2 sources encore mockées**, dont tout le pipeline aval est déjà réel. Objectif : les brancher en vrai.  

🟢 Implémenté — les 2 branchements (import HealthKit réel + courbe glycémique réelle) sont faits. HealthKitImportService gate le mock derrière `guard Self.disponible else { chargerMockInitial() }` (fallback simulateur/preview only), et `ActivitesSportService.reponse(pour:)` fetch les vrais `GlucoseReading` du hub. Ce chantier a servi de socle à S1 (voir doc « S1 — Réponse glycémique sport »).

---

---

## Ce qui est DÉJÀ réel (ne pas y toucher)
- **Modèle** : `ActiviteSportive`  = `@Model`  SwiftData (`id`  , `type: TypeSport`  , `dateDebut`  , `dureeMinutes`  , `intensite: IntensiteSport`  , `glucidesPreSport?`  , `note?`  , `source: SourceActivite`  .manuel/.healthKit, `healthKitData: HealthKitWorkoutData?`  , `iobAuDebut?`  ). Persistance réelle, lu via `FetchDescriptor<ActiviteSportive>`  .
- **Service hub** : `ActivitesSportService`  (`@Observable @MainActor`  , `Diaviz/services/hub/`  ) — lit/écrit vraiment SwiftData (`demarrer(contexte:)`  , `activites`  , `enregistrer`  avec IOB via `IOBService`  , `supprimer`  , `recharger`  ). `ActivitesSportServiceMock`  **n'existe plus**.
- **Saisie manuelle** : `SheetNouvelleActivite.swift`  → `service.enregistrer(...)`  → SwiftData. Édition via `DetailActiviteVue`  → `onEnregistrer`  , et `SheetEditionActiviteHealthKit.swift`  .
- **Couture analyses** : niveau de charge active du jour (`ContexteChargeActive`, remplace l'ancien `ChargeActivite` 7j le 2026-09-23) et `SportResume`  lisent le vrai hub (`ChargeurFaitsCoucher.sports`  ), consommés par B2/B3/coucher. Réel.
---

## Chantier 1 — Import Apple Health réel
>   ✅ **Fait** : `HealthKitImportService` requête désormais les vrais `HKWorkout` des 7 derniers jours (autorisation lecture `workoutType`, requête `HKSampleQueryDescriptor`, mapping `HKWorkout` → `WorkoutHealthKitCandidat` via `workout.statistics(for:)` pour FC moyenne/max, calories actives, distance). Fallback sur les mocks fixes uniquement quand HealthKit est indisponible (simulateur/preview). `workoutsImportes`/`workoutsIgnores` sont persistés en `UserDefaults` par `workoutUUID`. `NSHealthShareUsageDescription` étendue aux séances de sport. Le type mock a été renommé `WorkoutHealthKitMock` → `WorkoutHealthKitCandidat`.  

**Aujourd'hui** : `Diaviz/services/HealthKitImportService.swift` est un **mock**. `chargerMockInitial()` remplit `workoutsEnAttente` avec des `WorkoutHealthKitMock` en dur (`.mockCourse`, `.mockYoga` — définis dans `Diaviz/modeles/sport/WorkoutHealthKitMock.swift`). **Aucun** `import HealthKit` / `HKHealthStore` / `HKWorkout` dedans.

**Pipeline aval déjà réel** : sheet `Diaviz/vues/sport/Sheets/SheetImportAppleHealth.swift` → bouton « Importer » → `service.importer(...)` → `ActivitesSportService.enregistrer(...)` → SwiftData. Bandeau (`SportVue.swift`), badge d'onglet (`AppTabVues.swift`), entrée journal (`JournalVue.swift`) déjà branchés sur `importService`.

**À faire** :

- Autorisation lecture workouts (`HKObjectType.workoutType`  ) + requête des `HKWorkout`  récents via `HKHealthStore`  .
- Mapping `HKWorkout`  → workout en attente : FC moyenne/max, calories actives, distance → `HealthKitWorkoutData`  (le snapshot final est déjà réel).
- **Dédup persistante** : ne pas re-proposer un workout déjà importé/ignoré. Les sets `workoutsImportes`  /`workoutsIgnores`  existent mais sont **en mémoire** → à persister par `workoutUUID`  pour survivre au relaunch.
- **Config projet** : capability HealthKit déjà activée (`Diaviz.entitlements`  ). Mais `NSHealthShareUsageDescription`  (dans `project.pbxproj`  , `INFOPLIST_KEY_NSHealthShareUsageDescription`  ) **ne parle que des glycémies** → l'étendre aux séances de sport.
- **Référence de style** : `Diaviz/services/sante/HealthKitCGMService.swift`  (seul vrai usage HealthKit du projet).
- **Device-only** : HealthKit ne marche pas en simulateur → le build simulateur doit compiler et dégrader sans crash.
- **Renommage** : `WorkoutHealthKitMock`  perd son sens une fois la source réelle branchée → à proposer (touche plusieurs fichiers), pas d'office.
---

## Chantier 2 — Courbe glycémique réelle du détail d'activité
>   ✅ **Fait** : `reponse(pour:)` lit désormais les `GlucoseReading` réels du hub sur la fenêtre `[dateDebut − 30 min, dateFin + 30 min]` et produit le même `ReponseGlycemiqueSport`. `glycemieDebut`/`glycemieFin` sont ancrées sur les mesures les plus proches du début et de la fin **réels** de la séance (pas les bords de fenêtre). Retourne `nil` si moins de 3 `GlucoseReading` sur la fenêtre (état `.donneesManquantes`). Le générateur synthétique 3-phases est conservé uniquement sous `#if DEBUG` pour les previews.  

**Aujourd'hui** : `Diaviz/vues/sport/DetailActiviteVue.swift` affiche une courbe (`GraphiqueGlycemiqueSport`) alimentée par `ActivitesSportService.reponse(pour:)` → `genererReponse(...)`, un **générateur synthétique 3-phases** (helpers `glycemieAuTemps` / `deltaPendant` / `deltaApres` / `baselineDebut`). **Pas corrélé** aux vraies glycémies.

**À faire** :

- Remplacer `genererReponse`  par un **assembleur réel** lisant les `GlucoseReading`  du hub sur la fenêtre `[dateDebut − 30 min, dateFin + 30 min]`  .
- Produire le **même type** `ReponseGlycemiqueSport`  (`pointsCgm: [PointCgmSport]`  , `glycemieDebut`  , `glycemieFin`  , `deltaMgDl`  ) → signature inchangée, consommateurs intacts (`SportVue.etatsCourbes`  , `LigneActiviteSport`  , `MiniCourbeSport`  , `GraphiqueGlycemiqueSport`  , `DetailActiviteVue`  ).
- **Dégradation gracieuse** : peu/pas de `GlucoseReading`  sur la fenêtre → état vide signalé, pas de fausse courbe (comportement à trancher : vide vs partiel).
- **Frontière** : ce générateur est aussi la future brique de l'analyse **S1** (réponse glycémique au sport). Rester sur le détail d'activité cette itération, **ne pas déborder sur S1** (analyse séparée, non commencée).
---

## Points de décision (à valider avant de coder)
- ✅ Persistance des workouts importés/ignorés : `UserDefaults`  (`Set<String>`  de `workoutUUID`  ).
- ✅ Renommage : `WorkoutHealthKitMock`  → `WorkoutHealthKitCandidat`  .
- ✅ Comportement sans CGM : seuil de 3 points minimum, sinon état vide `.donneesManquantes`  (pas de courbe partielle).
---

## Méthode
1. Skills à invoquer : `swift6`  , `swiftui-ios26`  (+ `apple-hig`  si UI import/détail).
2. Explorer le code pour confirmer l'état réel avant de coder.
3. Concurrence Swift 6 stricte (isolation MainActor par défaut → types valeur partagés avec un actor = `nonisolated`  ). `HealthKitCGMService`  = référence HealthKit.
4. **Proposer un plan avant d'implémenter** ; attendre validation.
5. 2 chantiers indépendants, un lot de commits par chantier, build après chaque :
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme Diaviz -destination 'generic/platform=iOS Simulator' build`  **Ne pas toucher** : `@Model ActiviteSportive`  , saisie manuelle, `ActivitesSportService.enregistrer/supprimer/recharger`  , couture `ChargeActivite`  /B2/B3 — déjà réels. Uniquement les 2 sources mock ci-dessus.
## Au-delà des 2 chantiers (même itération)
- Refonte des graphiques glycémiques détail repas + sport — graphique en vedette pleine largeur sans carte, agrandi, échelle Y adaptative qui colle aux données avec marge autour des seuils 70/180.
- Refonte de la sheet détail nuit (`SheetDetailSoiree`  ) — courbe glycémie en hero + courbe IOB agrandie, même langage visuel.
- Nouvelle feature « Chrono en direct » de séance sportive avec Live Activity / Dynamic Island → voir la doc dédiée séparée.
