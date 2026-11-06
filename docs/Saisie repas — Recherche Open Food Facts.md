# Saisie repas — Recherche Open Food Facts
>   La saisie de repas est l'écran le plus important de l'app. L'onglet **« Produits »** (auparavant vide, qui ne cherchait que dans CIQUAL — aliments bruts, JSON local) est désormais branché sur l'API **Open Food Facts (OFF)**, sans avoir cassé CIQUAL ni « Mes aliments », en optimisant les appels réseau (quota limité).  

**Statut** : ✅ Implémenté — recherche Open Food Facts branchée sur l'onglet Produits · **Priorité** : ⭐⭐⭐⭐⭐ (cœur de l'app, cf. R1) · **Écran** : `Diaviz/vues/repas/Saisie/AjouterRepasVue.swift` 

---

## Ce qui a été implémenté
- `**Diaviz/services/RechercheProduitsService.swift**`  : service réseau réel (`@Observable @MainActor`  ), quota limité à 10 requêtes/min, cache mémoire session (terme → résultats), pagination des résultats. S'appuie sur `OpenFoodFactsAPIClient.shared`  .
- `**Diaviz/modeles/repas/AlimentOFF.swift**`  : struct représentant un produit OFF, nutriments optionnels (base collaborative, données parfois incomplètes), flag `glucidesRenseignes`  pour signaler l'absence de données fiables.
- `**Diaviz/modeles/repas/ResultatRechercheAliment.swift**`  : enum unifiant `.ciqual`  / `.off`  , consommé par toutes les vues de saisie — le modèle commun de recherche prévu au cadrage a finalement été réalisé via un enum plutôt qu'un protocole. C'est aussi le **point d'injection unique** de toutes les personnalisations par aliment (nom, emoji, glucides — voir « Personnalisations par aliment »).
- `**AlimentsRecentsService**`  généralisé aux deux sources via une clé composite source+id, avec migration douce des recents CIQUAL déjà enregistrés par les utilisateurs.
- Un **snapshot JSON** des produits OFF est persisté avec l'aliment récent, permettant de ré-résoudre un produit sans ré-appeler l'API. Le stockage a depuis migré d'UserDefaults vers le hub SwiftData (`AlimentRecentEnregistre`  ), donc synchronisé par CloudKit.
---

## Pourquoi
- La base CIQUAL couvre les aliments bruts/génériques, pas les **produits industriels** (marques, code-barres). L'utilisateur en a besoin au quotidien.
- L'onglet « Produits » existe déjà dans l'UI (capture) mais n'est câblé sur rien — c'est un cas d'enum sans effet.
- Le scanner code-barres est désormais implémenté (voir section dédiée en fin de doc).
---

## État du code
| Composant | Fichier | État |
| ----- | ----- | ----- |
| Écran de recherche | `Diaviz/vues/repas/Saisie/AjouterRepasVue.swift`  | `@State` local (`recherche`, `resultats`, `filtre: FiltreAliment` bruts/produits/mesAliments, `scannerCodeBarres`). Barre de recherche custom. Recherche CIQUAL déclenchée à **chaque frappe** via `.onChange(of: recherche)`, **synchrone**, aucun debounce (base locale). Menu `ellipsis.circle` : aliments masqués, aliments renommés, glucides corrigés, suppression du repas en cours, effacement des suggestions. |
| Modèle + service CIQUAL | `Diaviz/modeles/repas/AlimentCiqual.swift`  | `struct AlimentCiqual` (id `Int`, nom, glucides/sucres/protéines/lipides/calories /100g, emoji) + `CiqualService` (`@Observable`, singleton `.shared`, méthode **synchrone** `rechercher(_ terme:, limite:) -> [AlimentCiqual]`, charge `ciqual.json` du bundle au `init`, filtre les aliments masqués — voir section dédiée). |
| Récemment ajouté | `Diaviz/services/AlimentsRecentsService.swift`  | Persisté dans le **hub SwiftData** (`AlimentRecentEnregistre`), donc synchronisé CloudKit. Clé composite `"ciqual:123"` / `"off:3017620422003"` (= `ResultatRechercheAliment.id`), liste MRU plafonnée à 50. Porte aussi les préférences par aliment : dernière quantité, taille de portion, mode de quantité, glucides corrigés. |
| Saisie / persistance | `Diaviz/modeles/repas/EntreeAliment.swift`  | `EntreeAliment` référence un `ResultatRechercheAliment` (enum unifié), avec `quantiteGrammes` comme source de vérité et `modeQuantite` (grammes / portions). Le modèle SwiftData final `Aliment` (persisté) est **agnostique** (emoji/nom/quantité/glucides/insuline) et fige ses valeurs à la saisie. |
| Onglet « Produits » | idem écran | ✅ Implémenté — branché sur `RechercheProduitsService`. |
| Scanner code-barres | idem écran | ✅ Implémenté — voir section « Scan de code-barres ». |
---

## Cadrage initial — entièrement réalisé
Les quatre chantiers de ce cadrage (modèle commun de recherche, généralisation d'`AlimentsRecentsService`, client `OpenFoodFactsAPIClient`, optimisation des appels réseau) sont **tous livrés** — voir « Ce qui a été implémenté » et « État du code » ci-dessus pour la forme retenue. Les arbitrages laissés ouverts à l'époque ont été tranchés à l'implémentation :

- ✅ Debounce vs bouton « Rechercher » explicite pour OFF — tranché à l'implémentation (voir `RechercheProduitsService`  ).
- ✅ Forme de la clé composite dans `AlimentsRecentsService`  — tranchée à l'implémentation (source+id).
- ✅ Endpoint OFF exact + champs consommés + contraintes `User-Agent`  /rate — résolus dans `OpenFoodFactsAPIClient`  / `RechercheProduitsService`  (quota 10 req/min).
- ✅ Durée de vie du cache mémoire terme→résultats — résolue à l'implémentation (cache session dans `RechercheProduitsService`  ).
---

## Personnalisations par aliment
Trois corrections utilisateur se greffent sur le même référentiel partagé (CIQUAL local, Open Food Facts distant), qu'aucune des deux bases ne permet d'amender : **renommer**, **changer l'emoji**, **corriger les glucides pour 100 g**. Toutes suivent le même principe — ne jamais réécrire la base, stocker l'écart à part, et résoudre à l'affichage.

**Point d'injection unique** : `ResultatRechercheAliment` porte les computed `nom`, `emoji`, `glucides`, qui interrogent le service de personnalisation avant de retomber sur la valeur d'origine. Toute vue et tout calcul qui consomment cet enum suivent donc automatiquement, sans modification. Corollaire : ne jamais lire `AlimentCiqual.nom` ou `AlimentOFF.glucides` directement dans une vue.

### Renommage et emoji (CIQUAL uniquement)
`NomsPersonnalisesService` — `[Int: String]` par id CIQUAL pour le nom, idem pour l'emoji, persistés séparément. Réservé à CIQUAL : un produit OFF a déjà un nom et une marque propres au produit scanné, il n'y a pas de libellé générique à corriger.

- Édition depuis `DetailAlimentSheet`  : tap sur le titre (nom) ou sur l'emoji du hero. Restauration proposée dans l'alerte elle-même quand une personnalisation existe.
- Page de gestion « Aliments renommés » (`AlimentsRenommesSheet`  ), menu toolbar d'`AjouterRepasVue`  , restauration par swipe (nom et emoji séparément).
- **Rétroactif sur les repas déjà enregistrés**, contrairement aux glucides : `Aliment`  (hub) porte `idCiqualSource`  , et ses computed `nomAffiche`  /`emojiAffiche`  résolvent la personnalisation courante. `nom`  /`emoji`  stockés restent le fait historique inchangé — la signature de composition de « Repas à revoir » s'appuie dessus.
- **Rattrapage des repas antérieurs** à l'ajout d'`idCiqualSource`  (`nil`  sur tout l'historique) : un index inverse « nom d'origine → id », restreint aux seuls aliments personnalisés (quelques entrées, pas les ~3000 du référentiel), retrouve l'id par correspondance stricte. Le nom figé d'un repas antérieur est forcément le nom CIQUAL d'origine, la personnalisation n'existant pas encore.
### Correction des glucides pour 100 g (CIQUAL et OFF)
**Statut** : ✅ Implémenté · **Fichiers** : `Diaviz/services/AlimentsRecentsService.swift`, `Diaviz/modeles/repas/ResultatRechercheAliment.swift`, `Diaviz/vues/repas/Saisie/DetailAlimentSheet.swift`, `Diaviz/vues/repas/Saisie/AlimentsCorrigesSheet.swift`, `Diaviz/modeles/preferences/PreferencesAlimentsModeles.swift` 

Un produit scanné affiche parfois une valeur qui ne correspond pas à l'étiquette du paquet réel : OFF est collaborative et une même référence existe sous plusieurs fiches (emballages successifs, variantes pays). CIQUAL, de son côté, donne des moyennes génériques. Or les glucides pilotent la dose, le ratio effectif et les verdicts — une erreur de 6 g pour 100 g se propage à toute l'analyse.

- **Glucides seuls.** Seule valeur qui change quoi que ce soit aux analyses. Les sucres, protéines, lipides et calories restent ceux de la base. Garde-fou : `DetailAlimentSheet`  masque « dont sucres » si les sucres d'origine dépassent les glucides corrigés — un détail supérieur à son total se lirait comme un bug de l'app.
- **CIQUAL et OFF.** La clé composite couvre les deux sans surcoût.
- **Jamais rétroactif.** `Aliment.glucides`  est figé en `Int`  à l'enregistrement et alimente `ratioEffectifPersiste`  , `verdictPersiste`  , les buckets du mining et la signature de composition de « Repas à revoir ». Le repas a été dosé avec l'ancienne valeur : c'est la vérité historique. La réécrire fausserait l'analyse des ratios. C'est la différence de fond avec le renommage, purement cosmétique. Dit explicitement dans l'alerte de saisie.
- **Lève l'avertissement « glucides non renseignés »** : `ResultatRechercheAliment.glucidesRenseignes`  retourne `true`  dès qu'une correction existe, y compris sur un produit OFF sans valeur. Saisir l'étiquette est exactement la réponse à ce cas.
- **Signalement à trois endroits** : badge « corrigé » à côté du titre Glucides dans `DetailAlimentSheet`  , avec la valeur d'origine et « Restaurer » juste dessous ; crayon discret à côté du nom dans `LigneResultatRecherche`  (recherche et récents) ; page de gestion « Glucides corrigés » (`AlimentsCorrigesSheet`  ) dans le menu toolbar, restauration par swipe.
### Données durables vs état de saisie
`AlimentRecentEnregistre` porte deux natures de données, qui n'ont pas la même durée de vie :

- **État de saisie** (dernière quantité, snapshot OFF) : périmé dès que l'aliment sort de la liste MRU des 50 récents.
- **Décisions durables** (taille de portion, glucides corrigés) : doivent survivre à cette sortie, sinon elles seraient à ressaisir — la correction, paquet en main.
D'où la mécanique de `sauvegarder()`  : les clés à persister sont la liste MRU **plus** celles portant une donnée durable (`clesDurables` ). Ces lignes hors MRU sont écrites sans quantité, et marquées `estRecent = false` .
⚠️ **Bug corrigé au passage.** `recharger()` reconstruisait `clesRecentes` depuis _toutes_ les lignes du store : un aliment gardé pour sa seule taille de portion redevenait « récent » au redémarrage, et la liste dépassait silencieusement sa limite de 50. Le drapeau `AlimentRecentEnregistre.estRecent` (défaut `true`, donc compatible avec les lignes déjà écrites) distingue désormais les deux cas.

## Un produit OFF **corrigé** conserve aussi son snapshot hors MRU (`nettoyerSnapshots` et `sauvegarder`) : sans lui, `alimentsCorriges` ne saurait plus le résoudre et la page de gestion afficherait une correction sans nom ni marque. La correction elle-même survit de toute façon, indexée par code-barres — elle se réapplique au prochain scan.
## Quantité en portions
**Statut** : ✅ Implémenté · **Fichiers** : `Diaviz/modeles/repas/ModeQuantiteAliment.swift`, `Diaviz/modeles/repas/EntreeAliment.swift`, `Diaviz/services/AlimentsRecentsService.swift`, `Diaviz/vues/repas/Saisie/DetailAlimentSheet.swift` 

- Ni CIQUAL ni Open Food Facts n'exposent de taille de portion exploitable : c'est une méta-donnée purement locale, définie par l'utilisateur pour l'aliment (« 1 portion = 130 g »).
- Sélecteur segmenté « Grammes / Portions » dans la section Portion de `DetailAlimentSheet`  . En mode Portions, un `StepperDose`  (le composant partagé de toutes les saisies de dose) compte les portions au pas de 0,5, avec l'équivalent en grammes affiché en dessous.
- `EntreeAliment.quantiteGrammes`  **reste la source de vérité** pour tous les calculs nutritionnels, quel que soit le mode affiché — le mode n'est qu'une façon de la saisir.
- Le mode et la taille de portion sont mémorisés par aliment (`AlimentsRecentsService`  ) : le même mode est reproposé à la saisie suivante.
---

## Hors scope
- Onglet « Mes aliments » : toujours non branché sur une source de données.
- Correction des autres nutriments (sucres, protéines, lipides, calories) : seuls les glucides pilotent les analyses, les autres restent ceux de la base.
- Contribution des corrections vers Open Food Facts : l'app ne pousse rien, aucune écriture distante.
---

## Masquage des aliments CIQUAL des suggestions
**Statut** : ✅ Implémenté · **Fichiers** : `Diaviz/services/AlimentsCachesService.swift`, `Diaviz/vues/repas/Saisie/AlimentsCachesSheet.swift`, `Diaviz/modeles/repas/AlimentCiqual.swift` (filtrage dans `CiqualService.rechercher`), `Diaviz/services/AlimentsRecentsService.swift` (filtrage dans `alimentsRecents`)

Permet de retirer un aliment CIQUAL récurrent mais non pertinent (doublon, mauvaise traduction, entrée jamais utile) des suggestions — recherche **et** récents — avec une sheet de restauration accessible en permanence.

- **Geste** : swipe « Masquer » (destructif, `eye.slash`  ) sur une ligne de résultat CIQUAL uniquement. Les produits Open Food Facts n'ont pas ce geste — déjà choisis explicitement par une recherche, pas de bruit à filtrer.
- **Persistance** : `AlimentsCachesService`  (`@Observable`  singleton), `Set<Int>`  d'ids CIQUAL masqués. Même pattern que `AlimentsRecentsService`  .
- **Effet** : `CiqualService.rechercher(_:)`  exclut les ids masqués des résultats ; `AlimentsRecentsService.alimentsRecents`  filtre aussi les CIQUAL masqués (un aliment masqué disparaît de toutes les surfaces de suggestion).
- **Restauration** : sheet « Aliments masqués », accessible en permanence depuis le menu toolbar (`ellipsis.circle`  ) d'`AjouterRepasVue`  — liste les aliments masqués (nom, glucides/100g), swipe « Restaurer » pour chacun. État vide explicite si aucun aliment masqué.
---

## Scan de code-barres
**Statut** : ✅ Implémenté · **Fichiers** : `Diaviz/vues/repas/Saisie/ScannerCodeBarresVue.swift`, `Diaviz/services/OpenFoodFactsAPIClient.swift` (méthode `produit(codeBarres:)`), `Diaviz/vues/repas/Saisie/AjouterRepasVue.swift` 

Remplace le placeholder (`Text("Scanner un code-barres")`) par un scan réel appuyé sur VisionKit + l'API Produit OFF (distincte de la recherche texte Search-a-licious).

### Qui décode quoi
OFF ne lit pas d'image de code-barres : sa base est indexée par code-barres (EAN/GTIN), clé primaire de chaque produit. C'est **VisionKit** (`DataScannerViewController`), sur l'iPhone, qui décode l'image caméra en chiffres, localement, sans réseau. Ces chiffres sont ensuite envoyés à OFF pour un lookup direct. Pipeline : caméra → décodage local (VisionKit) → code-barres → requête OFF → produit ou « introuvable ».

### Scanner (`ScannerCodeBarresVue`)
- `UIViewControllerRepresentable`  autour de `DataScannerViewController`  — UI de scan native (viseur, mise au point, highlighting), pas d'AVFoundation bas niveau à maintenir.
- Symbologies : EAN-13 (quasi tous les produits européens), EAN-8 et UPC-E (petits emballages).
- **Scan unique** : le premier code-barres reconnu est remonté via `onCodeDetecte`  puis `stopScanning()`  est appelé — pas de mode continu. Un flag interne au `Coordinator`  empêche un double-déclenchement sur la même frame ; il n'a pas besoin d'être réinitialisable car chaque présentation de la sheet recrée un `Coordinator`  neuf.
- Fallback explicite (`ScannerIndisponibleVue`  ) si `DataScannerViewController.isSupported`  /`isAvailable`  est faux — simulateur (pas de caméra), device trop ancien, ou permission refusée. Pas d'écran noir silencieux.
- Permission : `NSCameraUsageDescription`  ajoutée aux build settings de la cible (Debug + Release).
### Lookup OFF (`OpenFoodFactsAPIClient.produit(codeBarres:)`)
- Endpoint Produit standard OFF v2 (`GET /api/v2/product/{code}.json`  ), **distinct** de l'endpoint Search-a-licious utilisé pour la recherche texte — lookup direct par code-barres, pas une recherche.
- Même stratégie de retry que la recherche texte (jusqu'à 2 tentatives sur 5xx/réseau, délai croissant), jamais sur 429/décodage.
- `nil`  — **pas une erreur** — si le code-barres n'est pas dans la base OFF (`status == 0`  dans la réponse, ou HTTP 404) : fréquent, la base est collaborative et inégalement complète selon marques/pays.
- Quota exact non re-vérifié à ce stade (probablement plus permissif que les 10 req/min de la recherche texte) — à surveiller si le scan devient un usage intensif.
### Flux dans `AjouterRepasVue` 
- Tap sur le bouton scanner (`barcode.viewfinder`  ) → sheet caméra (ou fallback si non supporté).
- Code détecté → sheet fermée **immédiatement** (scan unique) → lookup en tâche de fond.
- Trouvé → même flux qu'un résultat de recherche texte : `alimentSelectionne = .off(produit)`  → `DetailAlimentSheet`  . Aucune duplication de code entre scan et recherche.
- Introuvable ou erreur → alerte sur l'écran principal (jamais superposée à la caméra, déjà fermée) : message factuel + invite à chercher par nom dans l'onglet Produits.
- Produit trouvé mais aux glucides erronés → l'utilisateur corrige la valeur pour 100 g depuis `DetailAlimentSheet`  (voir « Correction des glucides pour 100 g »), plutôt que de chercher une autre fiche OFF.
### Ajustements post-validation utilisateur
Trois retouches faites après premier test réel sur device :

- **Retours haptiques dédiés** : `.sensoryFeedback`  distincts sur les 3 issues du scan — `.success`  (produit trouvé et exploitable), `.warning`  (introuvable, ou trouvé sans glucides), `.error`  (réseau/API). S'ajoutent au haptique déjà existant sur le masquage d'aliment.
- **Localisation VisionKit** : le premier test a montré les textes natifs de `DataScannerViewController`  ("Slow down.", "Find nearby barcodes") en anglais malgré un iPhone réglé en français. Cause : le projet ne déclarait aucune vraie ressource de localisation (`CFBundleLocalizations`  absent de l'Info.plist généré, malgré `knownRegions`  et même une tentative de forçage via `INFOPLIST_KEY_CFBundleLocalizations`  — cette clé n'est pas synthétisable de cette façon, sans effet constaté). Fix retenu : création de vraies ressources `Diaviz/fr.lproj/Localizable.strings`  et `Diaviz/en.lproj/Localizable.strings`  (contenu quasi vide, aucune chaîne de l'app n'étant extraite — tout le texte français reste en dur dans le code Swift). Leur simple présence comme ressources réelles du bundle (auto-détectées via le `PBXFileSystemSynchronizedRootGroup`  du dossier `Diaviz/`  ) a suffi à faire suivre VisionKit sur le français. Confirmé fonctionnel sur device.
- **Produit sans glucides → recherche de secours enrichie** : `lancerRechercheSecours`  inclut désormais la marque en plus du nom (`"\(nom) \(marque)"`  ) pour affiner la recherche de repli — un même produit apparaît souvent sous une fiche OFF différente (emballage variant) mieux renseignée, et la marque aide à cibler la bonne fiche parmi les résultats.
### Limite connue
Le simulateur iOS n'a pas de caméra : `DataScannerViewController` y est indisponible par construction (`ScannerIndisponibleVue` s'affiche). **Testé uniquement sur device physique.**
