# Mode démo

App « Diaviz Démo » : une seconde app, compilée depuis le même code, qui sert
à produire les captures d'écran du README sans jamais montrer de données
réelles.

## Ce qui la sépare de la vraie app

| | Diaviz | Diaviz Démo |
| --- | --- | --- |
| Configuration de build | Debug / Release | Demo (Debug + condition `DEMO`) |
| Identifiant | `fr.al3xdre.diaviz` | `fr.al3xdre.diaviz.demo` |
| Apple Santé | oui | **aucun droit** |
| iCloud / CloudKit | oui | **aucun droit**, tous les accès CloudKit court-circuités |
| Stockage | SwiftData persistant + CloudKit | SwiftData **en mémoire**, régénéré à chaque lancement |
| App Group du widget | `group.fr.al3xdre.diaviz.widget` | `group.fr.al3xdre.diaviz.demo.widget` |
| TestFlight | oui | jamais |

Aucun chemin ne mène aux vraies données : ni lecture Santé, ni synchronisation,
ni stockage partagé, ni widget commun.

## Données : une personne fictive

`GenerateurDemo` (dossier `Diaviz/demo/`) simule ~90 jours pour « Camille »,
avec un petit modèle physiologique (absorption des glucides, action de
l'insuline, dérive nocturne liée à la lente, effet du sport, bruit capteur).
Reproductible : même ancre (instant de génération) → même jeu. L'ancre est
l'heure du lancement, donc « aujourd'hui » est toujours rempli jusqu'à
maintenant.

Histoire racontée :

- J-89 → J-35 : charge habituelle, lente 18 u adaptée ;
- J-34 → aujourd'hui : préparation d'un semi-marathon (charge haute) ;
- J-31 : nuit avec hypo et resucrage, réveil visible dans le sommeil ;
- J-28 : lente 18 → 16 u ; J-21 : ratio du dîner 10 → 12 g/u ;
- petit-déjeuner un peu sous-dosé par le ratio configuré (écart visible dans
  « Écart de ratio »), déjeuner bien calibré ;
- pizza du vendredi récurrente, dernière occurrence hors cible (« Repas à revoir ») ;
- dessert pris 40 min après certains déjeuners (repas rapprochés, écartés) ;
- séances Apple Watch avec FC, marche soutenue, sommeil chaque nuit ;
- prises de glucides pendant l'effort : « préventif maintien » toutes les
  ~35 min sur les séances longues (≥ 70 min, hors musculation), « préventif
  anti-chute » juste avant une course intense ;
- corrections du coucher (21 h – 23 h, au-dessus de 185), jamais un soir de
  pizza ni la veille d'aujourd'hui ;
- aliments récents de la saisie déjà remplis (Ciqual : muesli, lait, banane,
  riz, pain complet, lentilles, pomme) ;
- stades de sommeil masqués sur les courbes de nuit (réglage de l'app) ;
- aujourd'hui : une bonne journée (accueil, widget).

Les lectures Apple Santé « en direct » (sommeil, pas et marche, séances et FC
de la charge active) sont remplacées par `LecteurChargeDemo` et
`LecteurSommeilDemo`, compilés uniquement avec `DEMO`. Le glucose passe déjà
par le hub : il est inséré directement.

Tests : `DiavizTests/GenerateurDemoTests.swift` (reproductibilité, crédibilité
glycémique, cohérence repas/bolus, présence de chaque élément de l'histoire).

## Refaire des captures

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme "Diaviz Démo" \
  -destination 'platform=iOS,id=<UDID>' -allowProvisioningUpdates build

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun devicectl device install app \
  --device <UDID> \
  <DerivedData>/Build/Products/Demo-iphoneos/Diaviz.app
```

Thème clair. Gestes : accueil (onglet Accueil) ; nuit avec sommeil (Analyses →
Analyse du coucher → Tendance basale → Nuit par nuit → Par nuit) ; écart de
ratio (Accueil → carte Analyse des ratios → onglet Petit déjeuner) ; séance
(Journal → Activités sportives → une course) ; Charge et glycémie (Analyses).

Recadrage : barre d'état (162 px) et barre d'onglets (300 px) retirées, largeur
réduite à 558 px. Fichiers dans `docs/images/captures/`.
