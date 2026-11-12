# S1 — Réponse glycémique sport
>  Corrèle chaque activité sportive au CGM du hub pour observer l'impact glycémique réel de l'effort, et juger factuellement ce qui a fonctionné pour rester stable. Jamais un ajustement de ratio (R2), jamais un calcul de dose en temps réel — l'app observe le passé, elle n'instruit pas le présent. 

**Statut** : 🟢 Implémenté (lots 1 à 4a) — mining agrégé (4b) non commencé
**Type** : statistique descriptive pure · **Priorité** : ⭐⭐⭐⭐

**Fichiers clés**

- `services/derivation/CalculVerdictsResucrage.swift`  — calculateur pur (verdicts, épisodes, fenêtres)
- `services/hub/ActivitesSportService.swift`  — `reponse(pour:)`  et `evenements(pour:)`  (corrélation temporelle)
- `vues/sport/FriseSeanceSportive.swift`  — courbe parcourable + liste couplée
- `vues/sport/EncartResultatPrise.swift` , `vues/sport/SheetExplicativeVerdictsResucrage.swift` 
- `vues/sport/ApercusFriseSeanceSportive.swift`  — 21 aperçus, un par cas de verdict
- `modeles/resucrage/`  — `Resucrage` , `IntentionResucrage` , `ResucrageAffiche` 
- `modeles/sport/`  — `StructureEffort` , `IntervallePauseSeance` , `EvenementActivite` 
- `composants/LigneEvenementCourbe.swift`  — ligne partagée avec le détail de nuit
---

## Pourquoi
- Le domaine sport était branché en réel côté hub, mais **aucune analyse ne l'exploitait**. `reponse(pour:)`  calculait un delta CGM par activité, jamais interprété.
- R1 **exclut** les repas ajustés pour « sport récent » de son mining (décision du 2026-08-05) — l'impact du sport était un angle mort complet.
- Hook posé et jamais rempli : `SportDetecte.nombreSeancesHistorique` , codé en dur à `0` .
- Précédent R1/B3 : jamais de modèle entraîné produisant une dose. S1 suit la même ligne.
---

## Ce que S1 fait
Répondre à : **qu'est-ce qui a fonctionné pour tenir la glycémie pendant cet effort ?**

Concrètement, sur le détail d'une activité : la courbe CGM parcourable au doigt, les événements qui l'expliquent (glucides, repas, corrections, pauses), et un verdict factuel pour chaque prise de glucides.

## Ce que S1 ne fait pas (redline)
- **Aucun calcul temps réel actionnable.** Pas de « prenez X g maintenant » à partir de la glycémie courante et du poids, même avec une formule issue de la littérature : c'est structurellement un conseiller de dose, interdit par CLAUDE.md (le principe vaut pour les glucides comme pour l'insuline).
- **Aucun repère de littérature affiché.** Les valeurs ci-dessous informent le calibrage interne, elles ne sortent jamais à l'écran. Précédent R1 : on ne montre que l'historique observé de l'utilisateur, jamais une convention généraliste.
- **Aucun jugement des doses d'insuline** — voir « Pourquoi les corrections ne sont pas jugées ».
- **Pas d'ajustement de ratio** : c'est R2, bloqué par S1.
---

## Modèle de données
### Resucrage — fait de hub indépendant
Décorrélé de tout repas et de toute activité **au niveau du modèle**. Le rattachement à une séance est déduit par fenêtre temporelle à la lecture, jamais stocké (même principe que `reponse(pour:)` pour le CGM).

- Aliments issus de la recherche (même moteur que la saisie repas) — la quantité seule ne suffit pas, le type de glucide compte.
- `glycemieCible: Double?`  optionnelle.
- **Intention déclarée obligatoire** : `correctifHypo`  / `preventifMaintien`  / `preventifAntiChute` . C'est elle qui définit ce que « réussi » veut dire. Seul l'utilisateur la connaît, elle ne se déduit pas des données ; sans elle, mélanger un correctif et un préventif dans la même statistique ne mesurerait rien.
- **Pas de champ index glycémique** : ni CIQUAL ni Open Food Facts ne l'exposent. L'intention déclarée sert de proxy suffisant — l'utilisateur choisit naturellement l'aliment adapté à son objectif.
- Les vues consomment `ResucrageAffiche`  (snapshot value type), jamais le `@Model`  : la relation cascade vers `Aliment`  invalidait les objets encore référencés par une row en cours d'animation de suppression.
### Glucides pré-sport — fusionnés dans le resucrage
La section de la sheet d'activité crée un `Resucrage` d'intention `preventifMaintien`, daté **30 min avant le début**, au lieu d'un champ propre à l'activité.

Motif : des glucides pris avant une séance visent exactement le même objectif que ceux pris pendant. Les garder à part en faisait la seule prise que l'analyse ne pourrait **jamais** juger, faute d'horodatage — alors que « qu'est-ce que je dois prendre avant de courir » est probablement la question la plus utile.

`ActiviteSportive.alimentsPreSport` reste sur le modèle pour les activités enregistrées avant ce changement.

### Structure d'effort — continu / fractionné
Champ sur `ActiviteSportive` et `SessionSportiveEnCours`, **obligatoire pour les sports cardio**, absent pour musculation/yoga/autre. Choisi avant le démarrage du chrono : cette information ne se rattrape pas après coup, et la littérature distingue ces régimes glycémiques.

### Fenêtres de pause
`IntervallePauseSeance` (`[début, fin]`), enregistrées à chaque reprise du chrono. Deux usages :

1. Situer un resucrage « pendant une pause ».
2. **Corriger** `**dateFin**`  : `dureeMinutes`  est la durée d'effort **net**, pauses déjà déduites. Sans les réintégrer, `dateFin`  sous-estimait la fin réelle en horloge murale, et toute fenêtre de corrélation coupait trop tôt.
---

## Algorithme de jugement
`CalculVerdictsResucrage` — calculateur pur, même famille que `CalculRatioObserve` et `CalculSituationsCoucher` : value types en entrée et sortie, aucun accès SwiftData, aucun modèle entraîné. Chaque verdict est recomptable à la main depuis les points CGM et les seuils du profil.

### Arbre de décision
```
Pour chaque prise de glucides
│
├─ Une correction d'insuline dans la fenêtre ?
│     └─ OUI → NON ÉVALUABLE (raison : correction d'insuline)
│              Deux effets opposés se mélangent. Règle prioritaire :
│              même un échec apparent devient ininterprétable, car
│              l'insuline a peut-être causé la chute.
│
├─ Un repas entre 1 h avant la prise et la fin de la fenêtre ?
│     └─ OUI → NON ÉVALUABLE (raison : repas proche)
│              Les glucides du repas agissent encore : rien n'est
│              attribuable à la prise seule. Masque aussi la
│              « chute non enrayée » ci-dessous.
│
├─ Une autre prise de glucides dans la fenêtre ?
│     ├─ C'est un correctif hypo, et la prise jugée est un préventif ?
│     │     └─ CHUTE NON ENRAYÉE
│     │        Avoir dû traiter une hypo EST le résultat du préventif —
│     │        on ne jette pas cette information derrière un silence.
│     └─ Sinon → NON ÉVALUABLE (raison : autre resucrage)
│
├─ Moins de 3 mesures CGM sur la fenêtre ?
│     └─ OUI → INDÉTERMINÉ (raison : mesures insuffisantes)
│
└─ Verdict selon l'intention déclarée
      │
      ├─ CORRECTIF HYPO — fenêtre : 30 min
      │     ├─ glycémie finale < seuil hypo ......... INSUFFISANT
      │     ├─ maximum > seuil hyper ................ REMONTÉ TROP HAUT
      │     └─ sinon ............................... REMONTÉ
      │
      ├─ PRÉVENTIF MAINTIEN — fenêtre : jusqu'à la fin de l'effort (min. 30 min)
      │     ├─ minimum < seuil hypo ................ CHUTE NON ENRAYÉE
      │     ├─ maximum > seuil hyper ............... MONTÉ TROP HAUT
      │     └─ sinon ............................... MAINTENU
      │
      └─ PRÉVENTIF ANTI-CHUTE — fenêtre : 30 min
            ├─ minimum < seuil hypo ................ CHUTE NON ENRAYÉE
            ├─ maximum > seuil hyper ............... MONTÉ TROP HAUT
            └─ sinon ............................... CHUTE ÉVITÉE
```
### Épisodes
Deux prises consécutives de **même intention** espacées de moins que le délai de jugement forment un même épisode : si la seconde arrive avant qu'on ait pu juger la première, leurs effets se mélangent.

Un **changement d'intention ouvre toujours un nouvel épisode**, même rapproché — passer de préventif à correctif est une décision différente.

### Pourquoi les corrections d'insuline ne sont pas jugées
Deux raisons, aucune n'étant de la prudence excessive :

1. **Confusion des causes.** Pendant un effort, l'exercice fait descendre la glycémie tout seul. Corriger à 200 et redescendre à 140 ne dit pas si c'est l'insuline, l'effort, ou les deux. Contrairement au resucrage, où l'effet glucidique est rapide et dominant sur une fenêtre courte.
2. **Échelle de temps.** Un analogue rapide agit sur 3-4 h avec un pic à 1-2 h. Une fenêtre de 30 min ne dit rien ; une fenêtre de 2 h déborde la séance et mélange encore plus de facteurs.
Un verdict « correction efficace » alors que c'est l'effort qui a travaillé induirait en erreur sur une décision de dose. C'est exactement la conclusion que l'app ne doit pas produire.

**Mais** leur présence invalide le jugement des glucides — voir l'arbre de décision.

---

## Seuils et leur origine
| Règle | Valeur | Origine |
| ----- | ----- | ----- |
| Délai de jugement d'une prise | 30 min | Cadence de contrôle glycémique pendant l'effort (ISPAD) |
| Regroupement en épisodes | 30 min | <p>**Dérivé**</p><p> : si une prise arrive avant qu'on ait pu juger la précédente, leurs effets se mélangent. Un seul chiffre au lieu de deux</p> |
| Fenêtre du préventif maintien | Jusqu'à la fin de l'effort, plancher 30 min | Maintenir, c'est tenir jusqu'au bout ; une fenêtre fixe ne dirait rien d'une course d'une heure. Le plancher évite de juger sur 3 min une prise faite juste avant la fin |
| Bornes hypo / hyper | Seuils du profil utilisateur | Aucune convention externe n'entre dans l'algorithme |
| Repas proche | De 1 h avant la prise à la fin de la fenêtre | Décision PO du 2026-11-12. Plus large, presque tout préventif suivant un dîner deviendrait non évaluable ; plus court, un repas pris 40 min avant fausserait le verdict sans le signaler. |
| Mesures CGM minimales | 3 sur la fenêtre | En dessous, `indéterminé` plutôt qu'un verdict sur une courbe trouée |
| Fenêtre de lecture de tendance | 15 min avant la prise, seuil ±10 mg/dL | Qualifie la pente en baisse / stable / hausse |
>  Un espacement d'épisode de **45 min** avait été proposé puis écarté : aucun fondement dans la littérature ni dérivation interne. Le 30 min le remplace, et se justifie tout seul. 

---

## UI
### Détail d'activité — courbe parcourable + liste couplée
Design retenu après itération sur six variantes (pills au-dessus, rail dédié, marqueurs sobres, timeline verticale, trois actes, curseur temporel).

**La courbe** porte la zone d'effort, les bandes grises de pause, et des points d'événements **discrets et sans libellé** — au-delà de quelques événements, des libellés sur la courbe deviennent illisibles.

**La liste** porte tout le détail sans troncature ni chevauchement, quel qu'en soit le nombre. C'est ce couplage qui règle le problème de densité.

**Les deux se répondent** : faire glisser le curseur met en évidence l'événement le plus proche (aimantation à 90 s, retour haptique) ; taper une ligne déplace le curseur.

**Repas du journal** (ajout du 2026-11-12 — l'hypothèse d'août « pas de repas pendant une séance » ne tient plus) : une ligne par repas pris dans la même fenêtre que les autres événements (30 min avant le début → 30 min après la fin), à son heure. Titre = moment du repas, à droite glucides et insuline. **Aucun point sur la courbe** (règle : ne pas charger un graphique existant) et pas d'aimantation du curseur dessus ; taper la ligne place le curseur à l'heure du repas, sans ouvrir de détail. Son bolus n'est pas répété en ligne « Correction ». Les aliments pré-sport des anciennes activités (sans horodatage) sont rangés à l'heure du départ.

**Barre de contexte au-dessus de la courbe**, hauteur fixe : pendant un scrub, le doigt masque tout ce qui est en dessous du point touché. Au repos elle affiche le bilan de la séance, pour que l'écran reste lisible sans interaction.

### Verdicts
- **Pastille** toujours visible, accolée au titre de la ligne.
- **Encart déplié au tap seulement** (jamais au passage du curseur, sinon la liste sauterait sous le doigt) : glycémie avant → après, fenêtre réellement observée et sa durée, tendance avant la prise, et la raison quand rien n'a pu être jugé.
- **Sheet explicative** accessible sous la liste, sur le modèle de `SheetExplicativeBasale`  (B1) — rend l'algorithme lisible plutôt que magique.
### Écran de séance live
Saisie d'une correction ou d'un resucrage sans quitter le chrono, plus un historique de la séance (temps depuis la dernière correction, IOB active, temps depuis le dernier resucrage, flux chronologique).

---

## Aperçus (21 scénarios)
`ApercusFriseSeanceSportive.swift`. **Les verdicts n'y sont jamais posés à la main** : chaque scénario fait passer ses données par `CalculVerdictsResucrage`, exactement comme le service réel. Un aperçu qui affiche un verdict incohérent avec sa courbe signale donc un vrai défaut de l'algorithme, pas une fixture mal écrite.

| # | Couverture |
| ----- | ----- |
| 01-03 | Correctif hypo : remonté / remonté trop haut / insuffisant |
| 04-07 | Préventif maintien : maintenu / chute via CGM / chute via correctif suivant / monté trop haut |
| 08-10 | Préventif anti-chute : chute évitée / non enrayée / monté trop haut |
| 11-16 | Non évaluable, épisode de 3 prises, trou CGM, prise pendant une pause, prise avant le départ, plancher 30 min |
| 17-21 | Séance vide, pré-sport seul, corrections seules, séance dense (8 événements), correction d'insuline invalidante |
---

## Littérature
Informe le calibrage interne. **Jamais affiché à l'utilisateur** — l'app ne montre que son propre historique observé.

### Deux mécanismes distincts, non substituables
- **Resucrage d'hypoglycémie** : sous 54 mg/dL → traiter, **arrêter** l'activité, ne pas reprendre avant remontée.
- **Supplémentation préventive** : démarre **avant** l'hypo, dès 126 mg/dL si la tendance baisse. Doses de 8-20 g (0,2-0,5 g/kg) toutes les 20-30 min selon la fréquence de contrôle.
### Dosage selon durée et insuline active (Riddell 2017)
L'IOB au départ peut modifier le besoin **d'un facteur deux** — et l'app capture déjà `iobAuDebut`.

| Durée | Peu d'insuline active | Beaucoup d'insuline active |
| ----- | ----- | ----- |
| 30-60 min | 10-15 g (aérobie modérée), 10-20 g (intense) | 15-30 g toutes les 30 min |
| 60-150 min | 30-60 g/h | jusqu'à 75 g/h |
### Seuils de démarrage et sécurité
- Glycémie de départ visée : **126-250 mg/dL**, stable, cétones basses.
- Sous 90 mg/dL : 10-20 g avant de démarrer. Entre 90 et 126 : 10 g suffisent.
- **Ne jamais démarrer avec des cétones positives** (risque d'acidocétose). Au-delà de 350 mg/dL, contrôler les cétones.
>  **Sur la borne haute** : l'ISPAD cite 15,0 mmol/L (270 mg/dL) comme limite de tolérance pendant l'effort. Ce n'est **pas une cible** — la référence adulte est 250 mg/dL, et faire du sport au-delà expose au risque cétonique. Le 270 avait été repris à tort dans un premier cadrage, puis écarté. 

### Hypoglycémie retardée post-effort
- Besoin en glucose démontré **7 à 11 h** après un effort d'après-midi.
- Majorité des événements **15-24 h** après.
- Sensibilité à l'insuline élevée **24-48 h**.
- Facteurs protecteurs : glycémie plus haute avant l'effort et au coucher, absence d'hypo pendant ou dans les 4 h suivant l'effort.
Cette fenêtre déborde largement S1 et **recoupe directement B1/B2**.

### Sur le choix rapide / lent
La littérature justifie le choix par la **fréquence de contrôle** (contrôle fréquent → IG élevé le plus efficace ; contrôle espacé → glucides lents tolérés pour limiter le rebond), **pas par la durée de l'effort**. L'hypothèse « glucide lent pour tenir sur la durée en aérobie » est plausible mais **non confirmée** en T1D par ces sources — à valider par les données propres de l'utilisateur.

### Sources
- [ISPAD Clinical Practice Consensus Guidelines 2022 — Exercise](https://onlinelibrary.wiley.com/doi/10.1111/pedi.13452)  · [texte intégral](https://pmc.ncbi.nlm.nih.gov/articles/PMC10107219/) 
- [Riddell et al. — Exercise management in type 1 diabetes: a consensus statement, Lancet D&E 2017](https://www.thelancet.com/article/S2213-8587(17)30014-1/abstract) 
- [Post-exercise recovery consensus, Lancet D&E 2021](https://www.thelancet.com/journals/landia/article/PIIS2213-8587(21)00054-1/abstract) 
- [Exercise, Hypoglycemia and Type 1 Diabetes (PMC)](https://pmc.ncbi.nlm.nih.gov/articles/PMC4029043/) 
- [Factors Associated With Nocturnal Hypoglycemia — T1DEXI](https://diabetesjournals.org/care/article-abstract/doi/10.2337/dc26-0381/170105/Factors-Associated-With-Nocturnal-Hypoglycemia) 
- [Carbohydrate Requirement for Exercise in T1D: Effects of Insulin Concentration (PMC)](https://pmc.ncbi.nlm.nih.gov/articles/PMC7645145/) 
- [Prolonged Exercise in T1D: Customizable Algorithm for Carbohydrate Supplements (PMC)](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC4412669/) 
---

## Décisions actées
### Cadrage (2026-08-06)
- S1 = observation seule, toujours rétrospective. Ratio = R2, hors périmètre.
- Resucrage : fait de hub décorrélé, section Journal dédiée, **intention obligatoire**, pas de champ IG.
- Aucune FK stockée entre activité et injection/resucrage — corrélation déduite à la lecture.
- Verdict « cible atteinte oui/non » abandonné au profit d'un groupement par intention puis par épisode.
- Fenêtres de pause persistées, `dateFin`  corrigé.
- **ML** : V1 en statistique descriptive pure. Le critère qui a fait écarter Random Forest pour B3 n'a jamais été « ML interdit » — c'est ce que la sortie représente (B2 utilise déjà k-NN en prod). Une similarité façon B2 reste envisageable en V2, toujours au registre observation.
- Repère littérature (0,2-0,5 g/kg) jamais affiché dans l'UI.
- Structure d'effort continu/fractionné : champ obligatoire pour les sports cardio, saisie manuelle.
### Verdicts et corrections (2026-08-07)
- **Glucides pré-sport fusionnés** avec le resucrage préventif maintien.
- **Les corrections d'insuline ne sont pas jugées** (confusion des causes + échelle de temps).
- **Une correction d'insuline dans la fenêtre rend le resucrage non évaluable** — règle prioritaire sur toutes les autres invalidations.
- **Trois raisons de non-jugement distinctes et nommées à l'écran** : autre resucrage, correction d'insuline, mesures insuffisantes.
- **Un correctif hypo suivant un préventif** classe celui-ci « chute non enrayée », pas « non évaluable ».
- Bornes = seuils du profil uniquement. Le 270 mg/dL écarté.
---

## Pistes à explorer
- **Croiser sport de la journée et résultat nocturne** — l'hypoglycémie retardée survient 7-24 h après l'effort et recoupe directement B1/B2. La piste la plus prometteuse.
- **Moduler la lecture par l'IOB au départ** — Riddell montre un facteur deux sur les besoins glucidiques. `iobAuDebut`  est déjà capturé.
- **Lot 4b — mining agrégé** par intention et par type d'effort, une fois assez de séances accumulées. Débloque aussi `SportDetecte.nombreSeancesHistorique` , toujours à `0` .
- **Comparer continu vs fractionné** — le champ existe, les données s'accumulent.
- **R2** — l'ajustement de ratio post-sport, débloqué par R1 et par S1.
