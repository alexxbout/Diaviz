# B1 — Détection basale inadaptée
>   Détecter si l'insuline lente est trop forte ou trop faible en lisant la **dérive glycémique du creux nocturne** — la seule fenêtre où la glycémie reflète l'action basale pure.  

**Statut** : 🟡 V1 en cours · **Type** : statistique descriptive · **Priorité** : ⭐⭐⭐⭐⭐ · 100% on-device
**Document unique** : produit + UX + algo + implémentation. (L'ancienne page « B1 — Assembleur » a été fusionnée ici.)

---

## Pourquoi
- L'utilisateur ne sait pas si ses hypos/hypers nocturnes viennent de sa **basale** ou de ses **bolus**.
- Sans outil, il faut plusieurs jours d'observation manuelle pour repérer une basale inadaptée.
- Besoin de distinguer « ajuster la basale » vs « ajuster les ratios » avec des faits objectifs à montrer au médecin.
- Formulations toujours **factuelles** (« tendance descendante observée »), jamais thérapeutiques.
## Quoi (ce que l'app remonte)
- Un **verdict** factuel : stable ✅, descendante ⚠️, ascendante ⚠️, **en amélioration** 🟢, nouvelle dose en observation ⏳, données insuffisantes ⏳.
- La **dérive** du creux nocturne (nuit profonde) avec direction.
- La **répartition** des zones analysées, les **hypos nocturnes**, les **resucrages avec rechute**, la glycémie moyenne au réveil.
- L'**historique de dose** de basale + reset automatique au changement.
---

## Interprétation du signal nocturne (fondements)
Base clinique qui cadre tout le reste de l'analyse :

- **Critère basal = ±30 mg/dL de dérive sur la nuit à jeun**, pas une pente instantanée. À jeun, sans sport, sans bolus résiduel, une glycémie stable à ±30 mg/dL = basale correcte ; une dérive constante au-delà = basale à ajuster. (≈ ±3–4 mg/dL/h sur une nuit, **pas ±1**.)
- **Le signal le plus propre = le creux nocturne (~minuit–3h/4h).** Avant, la glycémie subit encore le dîner/bolus ; après ~4h, elle est confondue par le **dawn phenomenon** (montée hépatique physiologique, >50% des patients, +20 à +50 mg/dL, ~04h–08h) **ou** par l'insuline lente qui faiblit (glargine surtout ; degludec plus plat).
- **La montée de fin de nuit est donc ambiguë** (dawn / waning / récupération post-hypo) → elle est **affichée comme contexte, jamais utilisée dans le verdict**.
- **Pas de Somogyi.** Les données CGM montrent que la glycémie du matin est plutôt _plus basse_ après une nuit avec hypo. Une montée matinale post-hypo vient surtout du **resucrage** (glucides), pas d'un rebond hormonal → **ne jamais attribuer une montée post-hypo à la basale**.Sources : [ADA — Dawn Phenomenon (Diabetes Care 2013)](https://diabetesjournals.org/care/article/36/12/3860/33148/Thirty-Years-of-Research-on-the-Dawn-Phenomenon)  · [StatPearls — Dawn Phenomenon](https://www.ncbi.nlm.nih.gov/books/NBK430893/)  · [CGM : absence d'effet Somogyi](https://pmc.ncbi.nlm.nih.gov/articles/PMC9553369/)  · [Basal testing ±30 mg/dL](https://integrateddiabetes.com/basal-testing/)  · [Degludec vs glargine, hypos nocturnes (Lancet BEGIN)](https://www.thelancet.com/journals/lancet/article/PIIS0140-6736(12)60204-9/abstract) 
---

## Zones dynamiques
>   **Cadrage à afficher en tête de section (le pourquoi/le quoi) :** la nuit est découpée en zones autour de la prise de lente. **Une seule zone décide du verdict — la nuit profonde.** Les autres servent de contexte (endormissement, aube, réveil).  

Zones ancrées sur l'heure de lente `L` :

| Zone | Fenêtre | Rôle | Dans le verdict ? |
| ----- | ----- | ----- | ----- |
| 1 — Pré-endo. | `L−3h → L`  | Contexte (sport, glycémie de départ). | Non |
| 2 — Endormissement | `L → L+2h`  | Détection hypo d'endormissement. | Non (contexte + répartition) |
| 3 — Nuit profonde (creux) | `L+2h → fin dynamique (dawn réel, ~04h à 06h max)`  | **Dérive basale. Signal principal.** | **Oui** |
| 4 — Dawn / fin de nuit | `fin dynamique → réveil`  | <p>Montée physiologique / waning. </p><p>**Contexte pour la dérive, mais les hypos y comptent.**</p> | Dérive non · hypos oui |
| 5 — Réveil | 1ʳᵉ activité | Glycémie de sortie (métrique). | Non |
Sur l'interface « Par nuit », le **statut de chaque zone = son rôle** (pas un générique « analysée ») : nuit profonde → « décide du verdict », endormissement → « détection hypo », pré-endo/dawn → « contexte ».

>   **Changement vs V1 initiale** : la fin de zone 3 passe de 05:00 à **~04:00 (début dawn)** pour ne pas capter la montée d'aube. Valeur exacte à finaliser (03h30–04h00).  

>   **Fin de zone 3 dynamique (2026-09-20)** : 04:00 n'est plus une coupure sèche. Passé cette heure, la zone 3 continue tant que la courbe reste plate — elle ne s'arrête que quand une vraie montée dawn est détectée (pente glissante > `seuilMonteeDawnMgDlH`, 15 mg/dL/h par défaut, lissée sur `fenetreDetectionMonteeMin`, **90 min**), avec un plafond dur à `dawnHeure + extensionDawnMaxH` (2h, donc 06h00 par défaut). **Cas qui a motivé le changement** : une nuit avec une lente prise peu après minuit finissait avec moins d'1h30 de zone 3 (coupée à 04h00, sous le seuil `dureeInsuffisante` de 1.5h) alors que la courbe restait parfaitement plate jusqu'au réveil sans aucun dawn — toute la matière était perdue pour rien. Détection volontairement légère (pente glissante, pas une vraie détection d'inflexion) : suffisante pour distinguer « ça monte » de « c'est plat », gardée simple. **Fenêtre relevée de 45 à 90 min le jour même** : à 45 min, un simple zigzag de bruit CGM (quelques mg/dL sur 45 min suffisent à dépasser +15 mg/dL/h) déclenchait la coupure dès la première fenêtre testée — donc pile à 04h00, comme avant le correctif. Le dawn phenomenon est une montée qui dure des heures (+20 à +50 mg/dL sur 04h–08h) : 90 min lisse le bruit sans retarder significativement la détection d'un vrai dawn. La vraie détection d'inflexion reste en V2 si ce seuil s'avère encore trop sensible à l'usage.  

### Exclusion PAR ZONE (jamais par nuit entière)
Une zone est écartée du calcul (pente non fiable) si, par ordre de priorité :

- nuit en mode pause → `modePause`
- durée < 1.5h → `dureeInsuffisante`
- couverture CGM < 80% → `cgmIncomplet`
- bolus de correction **dans** la zone → `bolusCorrection`
- **IOB résiduel > 0,5 u au début de la zone** → `iobResiduel`
- **resucrage dans la zone, avec ou sans épisode hypo associé** → `resucrage`
- **repas > seuil dans la zone ou dans les 5 h qui la précèdent** → `repasCopieux`
- **rapide non-correctif (repas/collation) dans la zone, sous le seuil copieux** → `bolusNonCorrectif`
- **la zone démarre dans les 90 min suivant la fin d'une hypo** → `rebondPostHypo`
- variabilité forte sur les **résidus** après retrait de la tendance (CV > 36%) → `chaotique`

**Principe des trois exclusions ajoutées le 2026-08-30 : ce qui compte est l'effet, pas l'horodatage.** Une zone n'était écartée que si un événement **tombait dedans**. Or la lente prise vers minuit place la zone 3 vers 02h — en plein dans la queue d'action des corrections du soir et dans la digestion d'un dîner tardif. Trois situations le montraient : une correction en fin de soirée faisait lire une tendance descendante marquée ; un dîner copieux et tardif faisait lire une forte tendance ascendante ; la retombée d'un rebond post-hypo faisait lire une forte tendance descendante. Aucun des trois ne disait quoi que ce soit de la basale.`seuilIOBResiduel`  était déclaré dans `ConfigBasale`  et n'avait **jamais été lu** ; `RaisonExclusion.iobResiduel`  n'était produite par aucun chemin. Le garde-fou était prévu puis oublié.

>   **Chantier 1 — deux trous comblés le 2026-09-27** (audit complet, 6 scénarios incohérents relevés) :  
>   1. **Resucrage préventif sans hypo** (glycémie jamais sous 70) échappait à toute exclusion — les glucides ne sont ni dans `repas`  (sortis vers `resucrages` ), ni détectés par l'ancien `resucrageDans`  (qui exigeait un épisode hypo). `resucrage`  exclut désormais la zone **avec ou sans** épisode hypo associé.  
>   2. **Rapide non-correctif sous le seuil copieux** (petite collation bolusée) passait à travers `bolusCorrection`  (pas une correction) et `repasCopieux`  (sous le seuil) — l'insuline injectée biaisait la pente sans aucune exclusion ni motif affiché. Nouvelle raison `bolusNonCorrectif`  pour ce cas résiduel.  

Ces nuits ne sont pas perdues : les corrections au coucher sont le sujet de B3.

### Signal indépendant de la pente (chantier 1, 2026-09-27)
**« Zone exclue de la régression » et « nuit exclue du verdict » sont désormais deux choses distinctes.** Avant, une zone exclue de la pente rendait la nuit entière `.exclue`, quoi qu'il se soit passé dessus — y compris une hypo ou une hyper qui aurait dû, à elle seule, trancher le verdict.

Deux signaux, calculés indépendamment de l'état de la pente :

- **`aHypoProfonde`** — un épisode hypo dans la zone 3 ou 4, **sauf** si l'IOB au moment précis du creux suffit à l'expliquer (> `seuilIOBResiduel`, une correction ou un repas récent — chantier 4, 28 sept.). Avant ce garde-fou, une hypo purement causée par une correction trop dosée forçait quand même « tendance basse », comme si la basale y était pour quelque chose.
- **`aHyperProfonde`** — un épisode au-dessus de `seuilHyper`  dans la zone 3 ou 4, **sauf** s'il est déjà expliqué par une cause identifiée qui chevauche temporellement l'épisode (dîner copieux en digestion, rebond post-hypo). Corrigée ou non par un bolus ne change rien — c'est l'excursion elle-même qui est le signal.

**Règle de sortie** : une nuit est `.exclue` (aucune information) seulement si **ni la pente ni un signal indépendant** ne sont disponibles. Sinon la nuit est `.valide`, avec la catégorie décidée par le signal indépendant en priorité (danger bas > danger haut), sinon par la pente. Quand c'est le signal qui décide seul (pente exclue), **aucun chiffre de dérive n'est affiché** — l'afficher mentirait sur la précision de la mesure (carte « Verdict de la nuit » → variante « signal sans pente fiable » ; sheet détail soirée → `ConstatB1Nuit.signalSansDerive`).

**Bug corrigé, exemple** : une hypo dans la zone 3, **resucrée normalement** (le geste attendu), excluait la zone (`resucrage`  ) — donc toute la nuit — et le déclencheur « 1 hypo profonde → tendance descendante immédiate » (voir Verdict + états ci-dessous) ne voyait jamais cette nuit puisqu'elle n'était plus dans les nuits valides. Cette alerte, censée être la plus rapide de toute l'analyse, ne se déclenchait donc que pour une hypo **non traitée** — traiter correctement son hypo désactivait l'alerte. Symétriquement côté haut : une hyper non expliquée qui recevait une correction (le geste attendu) excluait la zone (`bolusCorrection`  ) sans aucun mécanisme de secours pour la remonter au verdict — contrairement à l'hypo, rien ne la rattrapait avant `aHyperProfonde`.

>   **Chantier 4 — IOB explique une hypo (2026-09-28)** : `aHypoProfonde`  n'avait, lui, aucun filtre du tout — contrairement à `aHyperProfonde`  ci-dessus qui exclut déjà les hypers expliquées. Motivé par une nuit réelle (correction 2u à 23h01, creux à 63 mg/dL à 02h22, resucrage) où l'app affichait « tendance basse » et où l'hypothèse « c'est la correction, pas la basale » semblait plausible à l'œil. Le check `iobResiduel`  de zone ne regarde l'IOB qu'à un seul instant fixe (le début de la zone) : trop grossier pour ce rôle. `aHypoProfonde`  calcule désormais l'IOB au moment précis du **creux** de chaque épisode (seuil `seuilIOBResiduel` , 0,5u) — une hypo expliquée par une rapide récente (correction ou repas) ne force plus le verdict.  
>   **Vérification chiffrée après coup** : sur la nuit qui a motivé le chantier, l'écart réel (23h01 → 02h22 = 201 min) laisse une IOB de seulement **0,07u** pour une correction de 2u — bien en dessous du seuil. Cette hypo précise **n'est pas** rattrapée par le garde-fou : le verdict « tendance basse » qu'elle produit est correct, pas un bug. Le fix change bien le résultat pour une correction plus récente ou plus forte par rapport au creux (voir le test `hypoExpliqueeParIOB`, 3u à 90 min → IOB 1,6u → exclue) — juste pas sur cet exemple précis, où le délai est trop long pour qu'une seule correction de 2u explique toute la descente. Le compteur factuel « N hypos nocturnes » n'est pas affecté dans tous les cas : l'hypo reste comptée, seule son interprétation comme signal basale change.

>   **Chantier 2 — CV sur les résidus, pas sur les valeurs brutes (2026-09-27)** : le seuil `chaotique`  confondait deux signaux différents — une dérive **forte mais propre** (basale vraiment trop forte/faible) et un **vrai bruit** — les deux produisent le même coefficient de variation élevé sur les valeurs brutes. Avec l'extension dawn (20 sept., fenêtre pouvant courir jusqu'à 06h00), une fenêtre plus longue augmente mécaniquement les chances qu'une dérive propre dépasse le seuil au même titre que du bruit réel — pire la basale, plus de risque d'être jetée comme « chaotique » au lieu d'être comptée. Le CV se calcule désormais sur les **résidus** (mesure − droite de régression), pas sur les valeurs brutes : une pente propre laisse des résidus plats (CV bas) quelle que soit son amplitude, du vrai bruit garde des résidus dispersés quelle que soit la pente.

### Classification de la nuit profonde
Sur la **dérive totale** de la zone 3 (Δ mg/dL sur la fenêtre), pas sur une pente instantanée :

| Dérive zone 3 | Catégorie | Lecture basale |
| ----- | ----- | ----- |
| entre −30 et +30 mg/dL (paramètre `seuilDeriveStable`) | stable | adaptée |
| < −30 **ET** min. atteint proche de l'hypo (`seuilHypo` + marge 5 mg/dL) | descendante | <p>basale </p><p>**trop forte**</p> |
| > +30 **ET** max. atteint proche de l'hyper (`seuilHyper` − marge 5 mg/dL) | ascendante | <p>basale </p><p>**trop faible**</p> |
| dérive hors ±30 mais glycémie reste loin des deux seuils | stable | pas de signal alarmant |
>   ⚠️ Convention verrouillée : dérive **négative** (glycémie descend) = basale **trop élevée** = verdict `tropHaute`. **L'unité affichée partout à l'utilisateur est la dérive (Δ mg/dL par nuit)** — comparable au seuil ±30 — jamais la pente horaire (mg/dL/h), qui reste interne. Seuil calé à **30** (initialement 25 : trop strict, une nuit à +27 finissant à 120 était classée « ascendante »).  

>   **Garde-fou ajouté le 2026-09-13** : une dérive marquée qui ne s'approche jamais d'un seuil de danger réel n'est plus un verdict alarmant. Exemple : nuit à −32 mg/dL entre ~160 et ~90, jamais sous 70 → affichée « descendante » alors que factuellement rien à signaler. `categorie()` prend maintenant en option le min/max glycémique de la zone 3 ; en-dessous de `seuilHypo + 5` (resp. au-dessus de `seuilHyper − 5`) seulement, la dérive devient un verdict. Les seuils hypo/hyper viennent désormais du **profil** (`ProfilUtilisateur.seuilsGlycemiques`), plus figés à 70/180. Les recalculs locaux qui ignoraient le verdict déjà tranché (carte « Verdict de la nuit », sheet détail soirée) ont été alignés dessus — ils affichaient une catégorie différente de celle comptée dans le verdict global, source de badges incohérents à l'écran.  

**Priorité au danger bas : une nuit avec hypo profonde (zones 3+4) ne compte JAMAIS « stable ».** Une courbe globalement plate malgré une hypo doit sa stabilité au resucrage, pas à la basale — la nuit est classée **tendance basse** quel que soit le résultat de la régression, **et quel que soit l'état de la pente** (pente exclue par ailleurs ou pas — chantier 1). Hiérarchie de classification : rechute > série > prolongée > hypo profonde > **hyper profonde non expliquée** > dérive. Une hypo en zone 2 (endormissement) relève plutôt du dîner/bolus : avertissement affiché, mais la nuit ne bascule pas.

---

## Verdict + états
| Verdict | Condition | Réactivité |
| ----- | ----- | ----- |
| ⏳ Données insuffisantes | < 3 nuits valides | en attente |
| ⏳ Nouvelle dose en observation | changement de dose récent + < 3 nuits | en attente |
| ⚠️ Tendance descendante (`tropHaute`) | <p>1 hypo profonde (zones 3–4) </p><p>**OU**</p><p> resucrage avec rechute</p> | immédiat |
| ⚠️ Tendance ascendante (`tropBasse`) | 3 nuits zone 3 ascendantes | après 3 nuits |
| ✅ Stable (`adaptee`) | ≥ 3 nuits valides (par défaut, tant qu'aucun signal descendant récent ni ≥ 3 nuits récentes de même tendance non-stable ne déclenche un autre verdict) | après 3 nuits |
| <p>🟢 </p><p>**En amélioration**</p> | <p>verdict fenêtre « à revoir » </p><p>**mais**</p><p> les K dernières nuits valides reviennent vers stable</p> | glissant |
« Stable » est l'état par défaut dès le minimum de 3 nuits valides atteint : ce n'est pas un seuil positif de stabilité à atteindre, mais l'absence des signaux qui déclenchent `tendanceBasse` / `tendanceHaute` (hypo profonde, rechute, ou ≥ 3 nuits récentes majoritairement dans une même tendance). Décision actée le 2026-08-10 : le seuil initialement envisagé de 5 nuits stables + 0 hypo est abandonné au profit du comportement réel du code.

**Quand aucune dose n'a bougé**, l'état « nouvelle dose en observation » n'est plus annoncé : ce sont les exclusions qui vident la fenêtre, le titre affiché devient « pas assez de nuits exploitables ».

>   **Bug corrigé le 2026-09-27** : le déclencheur immédiat « 1 hypo profonde → tendance descendante » ne regarde que les nuits **valides**. Avant le chantier 1, une hypo resucrée excluait sa propre nuit (pente non fiable) — donc cette même nuit sortait de `valides`  et le déclencheur ne la voyait jamais. La règle « immédiat » ne s'appliquait en pratique qu'aux hypos **non traitées**. Avec le signal indépendant (section précédente), une hypo resucrée rend sa nuit `.valide`  quand même — le déclencheur fonctionne enfin pour le cas courant.

## Classement manuel d'une nuit (2026-11-08)
Sur une nuit passée, l'utilisateur peut remplacer le statut calculé : carte « Verdict de la nuit » → **Modifier**. La feuille montre le calcul de l'app (le choisir annule le classement) et les autres statuts : Concluante, Dérive montante, Dérive descendante, Hypo, Écartée. Pas de bouton sur la nuit en cours ni sur les 2 nuits d'observation après un changement de dose : elles ne comptent pas encore. Motif d'origine : une nuit écartée (« fenêtre trop courte ») que l'utilisateur estime exploitable.

| Statut choisi | Dans le verdict | Lente C1 |
| ----- | ----- | ----- |
| Concluante | nuit stable, retire tout déclenchement immédiat (hypo, rechute) | concluante |
| Dérive montante / descendante | tendance haute / basse | ratée |
| Hypo | tendance basse, **déclenche le verdict immédiat** comme une hypo détectée | hypo |
| Écartée | sort du verdict, motif « Écartée par vous » | non évaluable |

- **Le calcul reste connu** : la nuit affiche « Classée par vous » et « Calcul de l'app : … », la frise porte un petit crayon.
- **Les faits ne changent pas** : courbe et compteur d'hypos restent ceux du CGM. Une nuit classée « Hypo » sans épisode détecté n'ajoute rien au compteur.
- **Pas de dérive inventée** : une nuit que le calcul avait écartée entre dans le verdict sans chiffre de dérive, donc hors dérive moyenne.
- **Une nuit classée entre dans les 5 retenues** si elle est récente, et peut donc débloquer un premier verdict.
- **Un seul point d'application** : le classement est appliqué au calcul de la nuit, donc repris sans code dédié par tout ce qui lit une nuit (carte verdict, frise, timeline, répartition, accueil, détail de soirée, recherche du coucher, lente de C1). Chaque lancement du calcul doit juste lui transmettre les classements (`ConfigBasale.classementsManuels`) : 3 lancements aujourd'hui. Un nouveau lancement qui l'oublierait ignorerait les classements.
- **Stockage** : dans le profil (`PreferencesAvancees.classementsNuits`, par jour du soir de la nuit). Synchronisé iCloud, inclus dans l'export JSON, sans nouveau type à déployer dans CloudKit.
- **Hors périmètre** : B2/B3 comptent leurs hypos sur la courbe, un classement ne les modifie pas ; seule l'étiquette de nuit qu'elles affichent suit.

## Taxonomie des hypos nocturnes (signal vital)
Les hypos sont comptées sur la **fenêtre de sommeil complète** (endormissement → fin de nuit, **zone 4 incluse** : une hypo à 4h45 reste une hypo — seule la _dérive_ de la zone dawn est exclue du calcul).

**Ce qui compte comme un épisode (2026-10-20)** : un passage sous le seuil hypo ne devient un épisode que s'il dure **au moins 15 minutes** (3 relevés CGM consécutifs, chaque relevé couvrant 5 min) — définition du consensus international CGM (Battelino 2019). Sous le seuil sévère (54 mg/dL), l'épisode compte dès le premier relevé. Un passage plus bref (un ou deux relevés juste sous 70) reste visible sur la courbe de la nuit, mais n'entre ni dans les compteurs, ni dans la taxonomie, ni dans le verdict, ni dans les exclusions (rebond post-hypo), ni dans le garde-fou hypo de C1. Cas qui a motivé la règle : une nuit plate, avec seulement deux relevés juste sous 70 en fin de nuit — la nuit basculait en « hypos en série », et le verdict global en « tendance descendante » immédiate. Paramètres : `dureeMinEpisodeHypoMin` (15), `pasCGMMin` (5), `seuilSevere` (54).

Quatre patterns, détectés sur la courbe CGM + le log des resucrages :

| Pattern | Nom | Signal |
| ----- | ----- | ----- |
| 1 épisode court qui remonte | hypo | basale a poussé trop bas |
| 1 épisode continu ≥ 30 min sous 70 | hypo prolongée | basale maintient trop bas |
| <p>plusieurs épisodes < 60 min d'écart, </p><p>**sans correction entre**</p> | hypos en série | glycémie qui rase le seuil |
| resucrage correctif → remontée → nouvelle hypo < 60 min | resucrage avec rechute | correction insuffisante |
**Source des resucrages** : le modèle `Resucrage` du hub (section « Resucrage » du Journal, chemin principal, intention obligatoire) **et** les repas dont tous les aliments portent le badge `resucrage` (chemin secondaire, sans intention déclarée → traités en `correctifHypo`). Ces repas badgés sortent du tableau `repas` pour ne jamais être comptés deux fois. Le tableau `repas` ne sert plus qu'au repas ordinaire tardif.

**Resucrage vs remontée spontanée** : un épisode est « resucré » si une prise est enregistrée pendant l'hypo (fenêtre élargie à 20 min après son début). **Aucune prise enregistrée → remontée spontanée par principe** (contre-régulation, fin d'action d'insuline — ou compression du capteur). La phrase affichée reste factuelle : « remontée spontanée, sans resucrage enregistré ».

**Poids de l'intention** : l'intention déclarée pèse différemment selon la question posée.

| Question | Intentions retenues | Pourquoi |
| ----- | ----- | ----- |
| Zone 3 à exclure ? | les 3 | Des glucides restent des glucides : la courbe remonte, la régression est polluée, peu importe la raison. |
| Resucré ou spontané ? | les 3 | Une prise a bien eu lieu — dire « spontané » serait faux. |
| Rechute ? | `correctifHypo` seul | Une rechute dit « la correction a échoué » ; on ne peut échouer qu'une correction. |
Conséquence : une hypo qui suit un `preventifMaintien` ou `preventifAntiChute` exclut bien la zone et compte comme resucrée, mais reste une **hypo en série** — jamais une rechute. Le badge suit la hiérarchie : rechute > série > prolongée > hypo simple > dérive. Toutes valent « tendance basse » au verdict.

**V2 — compression capteur** : les fausses hypos par compression (dormir sur le capteur) ont une signature en V étroit (chute brutale + remontée immédiate, < 15–20 min). Détection d'inflexion à envisager pour les filtrer.

---

## Dico des métriques affichées (source unique par métrique)
| Métrique | Définition (cible) | Fenêtre | Seuil / note |
| ----- | ----- | ----- | ----- |
| Dérive nuit profonde | Δ mg/dL de la zone 3 (pente de régression × durée) | zone 3, nuits valides post-dose | <p>classée sur ±30 mg/dL </p><p>**+ proximité seuil hypo/hyper**</p> |
| Zones stables / basse / haute | zones 2+3 analysées, classées par leur dérive | fenêtre 3/7/14 j | basse = descendante, haute = ascendante |
| Zones exclues | zones 2/3 non analysables (motif) | idem | motif affiché |
| Hypos nocturnes | <p>**nb d'épisodes**</p><p> hypo (points contigus < 70)</p> | <p>fenêtre de sommeil complète (z2 → fin de nuit) ; </p><p>**nuits retenues**</p><p> dans la carte verdict</p> | <p>définition </p><p>**unique**</p> |
| Resucrages avec rechute | resucrage correctif suivi d'une nouvelle hypo < ~60 min | fenêtre comparable | mis en avant si > 0 |
| Glycémie moy. réveil | médiane des 30 dernières min, moyennée | zone 4/5, nuits valides | contexte, hors verdict |
| Dérive moy. | moyenne des dérives zone 3 des 5 dernières nuits valides | post-changement de dose | affichée en Δ mg/dL / nuit |
---

## Fenêtre, dose & reset
- Fenêtre glissante **14 nuits** (jours métaboliques 06h→06h). Min 3 nuits valides, idéal 5+.
- **Détection de dose** : regroupement des lentes par palier. Dose actuelle = dernier palier. `changementDoseRecent`  si < 30 j.
- **Reset** : seules les nuits **après** le dernier changement comptent dans la moyenne ; les nuits antérieures sont marquées (hors agrégat).
- Hypos / resucrages comptés sur toute la **fenêtre comparable** (hors nuit en cours), pas seulement les nuits valides.
- **Lente après minuit** : la « lente du soir » d'une nuit = la dernière lente du jour métabolique prise à ≥ 17h **ou après minuit avant 06h** (fin du jour métabolique). Une dose saisie à 00h30 appartient à la nuit en cours, pas au lendemain — sans cette règle, la nuit s'affichait à tort « sans lente ». Effet assumé : lente très tardive (ex. 01h) → zone 3 raccourcie, possiblement exclue pour durée insuffisante.
- **Seuil « dîner copieux » réglable** : Profil → Analyse du coucher, défaut **100 g**, plage 40–200 g par pas de 10 (`PreferencesAvancees.seuilRepasCopieuxNuit`  , repli `ConfigBasale.seuilRepasCopieuxParDefaut`  ). Plus le seuil est bas, plus de nuits sont écartées et plus les verdicts restants sont fiables. Ce n'est pas une affaire de lipides : chez ce patient, la seule quantité de glucides suffit à produire l'assimilation tardive.
## UI (ce que l'utilisateur voit)
- **Vue « Toutes »** : moyenne des nuits (courbe unique), bande de zone cible, seuils du profil, marqueur lente, sélecteur 3/7/14 j.
- **Vue « Par nuit »** : date picker, swipe horizontal pour changer de nuit, courbe colorée hypo/hyper, pills d'événements tappables, crosshair au scrub (heure + glycémie **+ stade de sommeil** à l'instant scrubé, coloré comme la bande sommeil — 2026-09-20), puis **carte « Verdict de la nuit »** et enfin le détail des zones.
- **Carte « Verdict de la nuit »** : badge suivant la hiérarchie **rechute > série > prolongée > hypo profonde > hyper profonde > dérive**, **dérive nette en Δ mg/dL** en héros, **jauge** ±30 (étendue ±60), le fait de mesure en texte lisible (« Mesuré de 02h06 à 04h00, soit 1 h 53 »), puis le poids dans le verdict : « Nuit stable, 2ᵉ des 5 retenues », cinq segments pleine largeur datés sous les remplis, et le compte de nuits écartées entre la première et la dernière retenue. Hypo zone 2 → avertissement orange, hors verdict. **Variante « signal sans pente fiable »** (chantier 1, 2026-09-27) : quand la pente est exclue mais qu'une hypo/hyper profonde tranche quand même le verdict — badge + motif de zone, pas de jauge ni de dérive chiffrée (mentirait sur la précision de la mesure).
- **Carte verdict globale** (refonte 2026-10-20) : une phrase de verdict (« Stable », « Tendance basse observée », « Tendance haute observée », « En amélioration », « Nouvelle dose en observation », « Pas encore de verdict »), une phrase qui dit sur quoi il repose (« Une hypo de 25 min la nuit du 12 mars suffit à ce verdict. Vos 4 autres nuits n'en montrent pas. »), puis la **frise des seules nuits du verdict** (5 au plus), pastilles groupées au centre : concluante (vert, coche), dérive (orange, flèche dans le sens de la dérive), hypo (rouge). Un tout petit point gris entre deux nuits retenues qui ne se suivent pas. Avant le premier verdict, des pastilles en pointillé bleu montrent les places encore à remplir. Toucher une nuit fait raconter cette nuit aux deux phrases ; la toucher à nouveau revient au verdict. Plus de chiffre en tête, plus de pastilles de contexte ni de compteurs dépliables : la dérive en héros (« +4 ») contredisait visuellement un verdict tiré par une hypo, et le compte « N analysées · M exclues sur 14 j » ne tombait pas juste. Textes : `ConstatVerdictBasale`, source unique partagée avec la carte d'accueil « Tendance nocturne », qui affiche désormais la même phrase de verdict avec une icône — plus « 6 nuits ↘ » (lu « 6 nuits descendantes ») ni « basale potentiellement trop élevée » (interprétation de dose). **Vocabulaire des nuits aligné sur la frise C1** : concluante / dérive / hypo, partout (carte verdict, carte « Verdict de la nuit », sheet détail soirée).
- **Périodes analysées** : timeline 14 nuits, 3 états + séparateur au changement de dose.
- **Répartition** (zones endormissement + nuit profonde, zone 3 alignée sur `categorieVerdict`  depuis le 27 sept. — source unique avec la carte verdict, zone 2 sans équivalent verdict garde son propre calcul) + **historique de dose**.
- **Guide de lecture** : bouton en pied de la page B1 → sheet expliquant ce que l'analyse mesure, les quatre verdicts avec leur courbe type, les motifs d'exclusion et ce que l'analyse ne dit pas. Courbes fabriquées, aucune donnée personnelle lue. Volontairement **hors Bibliothèque**, réservée aux faits de la littérature.**Fusion des deux cartes du haut (2026-08-30).** La carte « Sur quoi se base ce verdict » vivait sous la carte verdict et répétait nuits analysées, dérive moyenne et nuits exclues ; seuls ses motifs étaient uniques. Elle est supprimée, les motifs passent en ligne dépliable de la carte verdict.**Une seule fenêtre par carte.** Le compteur d'hypos portait sur 14 jours et cohabitait avec « en amélioration », calculé sur 5 nuits : deux échelles de temps dans un même bloc, que rien ne distinguait à la lecture — d'où une impression de contradiction. Il porte désormais sur les nuits retenues.
**Peau commune des graphiques.** Les graphiques de glycémie de l'app ne partagent pas leur code — `GraphiqueGlycemique` sert repas et sport, B1 a le sien (zones de nuit, crosshair, pills tappables, coloration par segment, qui n'existent nulle part ailleurs). Ce qui doit se **ressembler** vit dans `StyleGrapheGlycemie` : épaisseurs, pointillés, opacités, teintes de seuil, hauteurs, plus les marks de bande cible et de lignes de seuil. B1 y gagne la bande de zone cible, perd ses annotations « 70 » / « 180 » redondantes avec l'axe Y, et lit enfin les **seuils du profil** — ils y étaient figés à 70/180, si bien que changer ses seuils dans les réglages n'avait aucun effet sur ce graphique alors que repas et sport suivaient.

---

## Annexe — Architecture & implémentation
« Un hub, des dérivations » : le hub SwiftData ne stocke que des faits bruts horodatés ; B1 **lit** et recalcule tout à la volée, rien n'est persisté.

| Composant | Fichier | Rôle |
| ----- | ----- | ----- |
| `CalculAnalyseBasale`  | `services/derivation/`  | Calculateur **pur** (`nonisolated`, Sendable, value types). Zones, dérive, exclusions, verdict, dose. |
| `AnalyseBasaleService`  | `services/hub/`  | Service `@Observable @MainActor` : lit le hub au boot, mappe en value types, délègue, expose `analyse`. Re-sync au retour sur la page. |
| `ChargeurFaitsCoucher`  | `services/hub/`  | Chargeurs partagés B1/B2/B3 — dont `resucrages` (modèle `Resucrage` + repas badgés) et `repasHorsResucrage` . |
| `StyleGrapheGlycemie`  | `composants/`  | Peau commune des graphiques de glycémie (traits, opacités, teintes de seuil, bande cible). |
- **Entrées hub** : `GlucoseReading`  , `Injection`  (lente/rapide/motif), `Repas`  , `Resucrage`  , `ActiviteSportive`  , `PeriodePause`  , `ProfilUtilisateur`  , `ScoreService.debutJourMetabolique`  , `IOBCalculateur`  .
- **Grille d'affichage** : chaque nuit rééchantillonnée sur 121 points (21h→07h, 5 min) pour la moyenne point-à-point sans crash. Couverture/exclusions calculées sur le **brut**.
- Sortie : un `AnalyseBasaleDetail`  plat consommé tel quel par l'UI (dont `deriveMoyenne`  , l'unité montrée à l'utilisateur, et `BilanHyposNuit`  par nuit).
## État d'implémentation (fait)
Les points listés ci-dessous sont implémentés dans le code. Les valeurs numériques sont des **paramètres ajustables**.

1. **Seuil de classification** : dérive totale **±30 mg/dL** (aligné clinique ; d'abord 25, remonté à 30 — une nuit à +27 finissant à 120 était classée à tort « ascendante »).
2. **Fin de zone 3** : 04:00 (au lieu de 05:00), pour exclure la montée d'aube.
3. **Resucrage avec rechute** : resucrage d'intention `correctifHypo`  pendant une hypo → remontée → nouvelle hypo < 60 min.
4. **État « en amélioration »** : implémenté (K = 5 dernières nuits valides).
5. **Recency du verdict** : la tendance (ascendante / descendante) est calculée sur les **5 dernières nuits valides**, pas sur n'importe quelles nuits de la fenêtre 14 j.
6. **Définitions unifiées** : hypos et resucrages ont une seule source de calcul (compteurs par nuit, réutilisés partout).
7. **Pas de Somogyi** : une montée post-hypo n'est jamais attribuée à la basale.
8. **Unité d'affichage = dérive** : la dérive (Δ mg/dL) remplace la pente horaire partout dans l'UI (`deriveMoyenne`  dans le modèle, carte « Verdict de la nuit », bloc fondements).
9. **Carte « Verdict de la nuit »** : badge + dérive + jauge ±30 + phrase de position + poids dans le verdict, en tête de la vue « Par nuit ».
10. **Priorité hypo dans le verdict de nuit** : hypo profonde (zones 3+4) → la nuit est classée « tendance basse » dans les compteurs (jamais stable), badge rouge sur la carte, hypo zone 2 → simple avertissement (dîner/bolus, hors verdict basale).
11. **Taxonomie des hypos** : `BilanHyposNuit`  calculé sur la fenêtre de sommeil complète (zone 4 incluse) — hypo / prolongée (≥ 30 min) / en série (< 60 min d'écart sans correction entre) / rechute (resucrage correctif requis) ; resucrage = prise < 20 min après le début de l'épisode, sinon remontée spontanée.
12. **Resucrages branchés sur le hub** : B1 lit le modèle `Resucrage`  (+ repas entièrement badgés `resucrage`  ) via `ChargeurFaitsCoucher.resucrages`  , et non plus le seul tableau `repas`  — qui devient `repasHorsResucrage`  côté B1 pour éviter le double comptage. Pondération de l'intention (option 2) : toutes pour l'exclusion de zone et le libellé resucré/spontané, `correctifHypo`  seul pour la rechute. Les pills `.resucrage`  du graphique, jusqu'ici jamais émises, le sont enfin.
13. **Exclusions d'effet résiduel** : IOB au début de zone (> 0,5 u), repas copieux étendu aux 5 h précédentes, rebond post-hypo (90 min). Le seuil repas devient un réglage utilisateur (défaut 100 g).
14. **Carte verdict fusionnée** : « Sur quoi se base ce verdict » fondue dedans, hypos ramenées à la fenêtre des nuits retenues, motifs d'exclusion dépliables, titre honnête quand la dose n'a pas bougé.
15. **Peau commune des graphiques** : `StyleGrapheGlycemie`  porte épaisseurs, pointillés, opacités et teintes de seuil, consommé par B1 comme par `GraphiqueGlycemique`  (repas/sport). B1 gagne la bande de zone cible et lit enfin les seuils du profil, qui étaient figés à 70/180.
16. **Guide de lecture** : sheet accessible depuis un bouton en pied de page B1 — principe de la mesure, quatre verdicts avec courbe type, motifs d'exclusion, limites assumées.
17. **Garde-fou dérive-sans-danger (2026-09-13)** : une dérive hors ±30 mg/dL ne bascule plus le verdict si la glycémie de la zone 3 ne s'approche jamais d'un seuil hypo/hyper (marge 5 mg/dL). Seuils hypo/hyper désormais lus depuis le profil (`ProfilUtilisateur.seuilsGlycemiques` ), plus figés à 70/180 dans `ConfigBasale` . Les deux recalculs locaux qui affichaient un badge différent du verdict déjà tranché (carte « Verdict de la nuit » dans `CourbesNocturnesChart` , constat B1 de la sheet détail soirée dans `CalculDetailSoiree` ) lisent désormais `categorieVerdict`  au lieu de recalculer sur la seule dérive.
18. **Fin de zone 3 dynamique (2026-09-20)** : la borne dawn (04:00) n'exclut plus une nuit plate faute de fenêtre. `finZone3Dynamique`  avance par pas de 15 min tant qu'aucune montée soutenue n'est détectée (pente glissante sur `fenetreDetectionMonteeMin` , **90 min** — relevé le jour même de 45 min, trop court : un simple zigzag de bruit CGM y dépassait le seuil et coupait encore pile à 04h00 ; seuil `seuilMonteeDawnMgDlH` , 15 mg/dL/h), plafonnée à `dawnHeure + extensionDawnMaxH`  (2h, soit 06:00). Motivé par une nuit à lente tardive (00h31) exclue pour `dureeInsuffisante`  (1.5h) alors que sa courbe restait plate jusqu'au réveil, sans aucun dawn réel.
19. **Chantier 1 — signal indépendant de la pente (2026-09-27)** : audit complet des scénarios couverts par le code vs la doc, 6 cas incohérents relevés. `aHyperProfonde`  ajouté (symétrique de `aHypoProfonde` , exclut les hypers déjà expliquées par un dîner copieux ou un rebond post-hypo). Une nuit devient `.exclue`  seulement si ni la pente ni un signal indépendant ne sont disponibles — sinon `.valide` , dérive chiffrée masquée si la pente elle-même est exclue. Corrige : hypo resucrée qui désactivait le déclencheur immédiat de tendance descendante, hyper corrigée qui disparaissait sans aucun signal de tendance ascendante. Deux trous d'exclusion comblés en même temps : resucrage préventif sans hypo (`resucrage`  n'exige plus un épisode hypo associé), rapide non-correctif sous le seuil copieux (nouvelle raison `bolusNonCorrectif` ).
20. **Chantiers 2 et 3 (2026-09-27)** : `chaotique`  se calcule désormais sur le CV des **résidus** (mesure − droite de régression), pas sur les valeurs brutes — une dérive forte mais propre ne se fait plus jeter comme du bruit, surtout sur les fenêtres longues permises par l'extension dawn. La carte « Répartition » (`AnalyseBasaleDetail.basalDistribution` ) ne recalcule plus la classification de la zone 3 — elle lit `categorieVerdict`  (même source que la carte verdict principale, garde-fous inclus), éliminant les chiffres divergents entre les deux cartes pour les mêmes nuits.
21. **Chantier 4 — IOB explique une hypo (2026-09-28)** : `aHypoProfonde`  ne force plus « tendance basse » quand l'IOB au moment précis du creux (pas un instant fixe comme `iobResiduel`  de zone) dépasse `seuilIOBResiduel`  — une hypo causée par une correction ou un repas récent n'est pas un signal basale. Symétrique de l'« expliquée » déjà présent sur `aHyperProfonde`  (chantier 1), qui n'avait jamais reçu son équivalent côté hypo.
22. **Règle des 15 min et refonte de la carte verdict (2026-10-20)** : un passage sous le seuil hypo ne compte qu'à partir de 15 min (ou sous 54), voir Taxonomie. Nouvelle carte verdict (phrase, explication, frise touchable des nuits du verdict), carte d'accueil alignée sur la même phrase, vocabulaire concluante / dérive / hypo commun avec C1.
## Évolution & dépendances
- **V2** : transition zone 2→3 adaptative ; resucrage disproportionné ; vraie détection d'inflexion dawn si le seuil de pente glissante actuel s'avère trop grossier à l'usage ; **compression capteur** (filtrage des fausses hypos en V étroit).
- **V3** : sparkline de trajectoire (pente nuit par nuit) ; drapeaux de contexte (sport 7 j, IOB).
- **Dépendances** : B1 → B2 (endormissement) → B3 (corrections) → RB1.
