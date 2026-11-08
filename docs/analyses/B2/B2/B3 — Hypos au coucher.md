# B2/B3 — Hypos au coucher (endormissement + corrections du soir)
>   Remonter les hypos survenues au coucher : soit à l'endormissement sans correction prise (B2), soit après une correction rapide qui a trop fait descendre (B3). Le schéma de correction standard ne marche d'ailleurs pas bien le soir (effet cumulé rapide + lente). Des **faits**, jamais un verdict ni une dose à prendre.  

**Statut** : 🟢 Implémenté (calcul + UI réelle branchée sur le hub) · **Type** : Statistique descriptive pure — faits comptés + recherche par filtres explicites, aucun modèle · **Priorité** : ⭐⭐⭐⭐

---

---

## Pourquoi
- Un DT1 sous stylo se pose très souvent, le soir quand sa glycémie n'est pas haute, **une vraie question** : « peut-on se coucher comme ça, ou faut-il prendre des glucides — sachant que j'ai fait du sport / qu'il me reste de l'insuline active ? »
- Symétriquement, quand la glycémie est haute et qu'une correction est prise au coucher, le ratio standard provoque parfois des hypos à cause de l'effet cumulé avec la lente. L'utilisateur ajuste empiriquement (« je fais moins ») mais sans données pour calibrer — 9/10 ça marche, mais les échecs sont imprévisibles et dangereux.
- Rien n'agrège glycémie au coucher + sport + IOB + dose de lente + correction au même endroit pour éclairer ces deux décisions.
- La charge mentale du diabète fait perdre la bonne décision **faute d'un endroit clair où l'info vit**. Le cerveau retient le risque, pas la solution. Cette analyse **rend la confiance**, elle ne décide pas.
- Insight central : une lente jugée **adaptée par B1** (nuit profonde stable) peut **quand même** provoquer une hypo à l'endormissement si on part d'une glycémie modeste, ou après une correction trop généreuse. Ce plancher pratique est invisible à B1 — par construction B1 regarde la nuit profonde, pas l'endormissement.
- Problème non-déterministe, multi-facteurs en interaction (glycémie, IOB, sport, charge de la semaine, dose lente, temps depuis le repas) → impossible à résoudre par des règles simples — d'où le parti pris : compter des faits et lister les soirs comparables, plutôt que d'inférer une règle sur un historique de quelques dizaines de nuits.
---

---

## Quoi
- **Population fusionnée** = union de deux populations : couchers avec glycémie **sous un seuil configurable** (« seuil de coucher analysé », défaut ≈ 160 mg/dL) **sans correction** (branche B2) + soirs avec **correction rapide prise au coucher**, quelle que soit la glycémie de départ (branche B3, event-based). Le coucher ≥ 160 **sans correction** reste hors analyse (zone de confort, non analysée).
- **Frontière B2/B3** = présence ou non d'une correction rapide au coucher. Pas de seuil de glycémie côté B3 : c'est l'acte de correction qui déclenche.
- **Issue observée (focus hypo)** : hypo dans les **zones 1-2** (≈ 2h post-lente pour B2 ; fenêtre 2h/6h post-correction pour B3). Déclenchée par un passage soutenu sous le seuil hypo configuré, **ou** par un resucrage d'intention `correctifHypo`  loggé sans creux CGM visible — l'utilisateur a confirmé l'hypo, le capteur l'a manquée (retard CGM, correction très rapide). Affichée en **temps relatif à la lente**.
- **Hypo évitée** (troisième état, ajouté le 2026-08-29) : un resucrage **préventif** (`preventifMaintien`  / `preventifAntiChute`  ) pris dans la fenêtre de coucher **sans** passage sous le seuil. Ni hypo (la glycémie n'est jamais descendue), ni stable (l'utilisateur a dû intervenir). Sans cet état, trois soirs très différents se confondaient dans « stable » : rien fait/rien passé, resucré par précaution, et resucré _ce qui a évité l'hypo_ — le plus instructif des trois disparaissait, et le mining apprenait qu'une situation était sûre alors qu'elle ne l'était que grâce à l'intervention. **Hors du compteur d'hypos** (ce n'en est pas une), mais compté et affiché sur sa propre ligne : « dont N hypos évitées par resucrage ».
- **Classification B3 à 3 états** (conservée côté calcul, visible au détail des soirs mais ne pilote plus la page qui reste focus-hypo) : **insuffisante** (glycémie reste haute > 2h), **adaptée** (retour en cible sans hypo), **sur-correction** (hypo dans les 6h). La sur-correction est l'événement dangereux, prioritaire.
- **Sortie = des faits, toujours avec dénominateur.** Jamais de chiffre-cible, jamais de conseil de glucides ou de dose. Garde-fou affiché : « ce qui s'est passé, pas une dose à prendre ». L'utilisateur conclut.
- **Fenêtre** : le tableau de la page ne montre que les nuits **depuis le dernier changement de dose de lente** (les seules comparables à aujourd'hui). La dose actuelle est affichée une fois, en carte d'en-tête. L'historique complet reste conservé pour la recherche par similarité (corpus 60 nuits, sans ce reset).
- **Tableau event-first** : par défaut seules les **hypos** sont listées (rares → borné) ; les nuits stables sont résumées en compteur ; « Voir tout » déplie la liste complète, triable par date ou par glycémie.
- **Charge d'activité** : signal de contexte transverse affiché par ligne — depuis le 2026-09-23, niveau de **charge active** du jour (basse / normale / haute, voir `docs/architecture/Diaviz — Charge active (sport).md`), affiché seulement hors normale ; auparavant charge sportive sur 7 jours glissants. Explique les hypos « inexpliquées » — sport non loggé ce soir-là mais semaine chargée (sensibilité accrue plusieurs jours).
- **Recherche « Comparer à ce soir »** : saisir la glycémie actuelle, puis restreindre par des **critères de contexte activables** (même sport, même type de séance, même charge de la semaine, insuline encore active). Les soirs passés retenus sont scindés fini en hypo / resté stable, avec leur contexte. Chaque critère affiche l'effectif qui resterait s'il était activé.
## Comment
### Données (réutilise B1)
- Colonne vertébrale = `NightChartData`  : glycémie au coucher, heure + dose de lente, zones 1-2, events (hypo / resucrage / correction).
- **IOB résiduel au coucher** : calculé (formule DIA sur les rapides récentes, dîner + correction).
- **Sport du jour + charge 7j** : via le service activités.
- **Seuils** : seuil hypo du profil + réglage « seuil de coucher analysé » + cible haute du profil (déclenchement classification B3).
- **Fenêtrage du tableau** = depuis le dernier changement de dose. Les données ne sont pas supprimées (la recherche par similarité garde tout l'historique récent).
- **Resucrages** : lus depuis le modèle `Resucrage`  du hub (section « Resucrage » du Journal) + les repas entièrement badgés `resucrage`  , via `ChargeurFaitsCoucher.resucrages`  . Le tableau `repas`  devient `repasHorsResucrage`  pour éviter le double comptage. L'**intention déclarée** distingue une hypo traitée (`correctifHypo`  ) d'une hypo évitée (préventifs) — jamais déduite.
### Distinction B1 / B2-B3
- **B1** = déterministe : pente basale de la nuit profonde (zone 3), **exclut** les zones polluées (IOB, rapide, sport, chaotique).
- **B2/B3** = remontée d'événements sur les zones 1-2 (endormissement) : **garde** ces nuits sales et cible l'endormissement/la correction. Deux sujets différents, pas une contradiction (zone 3 ≠ zones 1-2).
### Features suivies par soir (référence, pas un modèle ML)
| Feature | Source |
| ----- | ----- |
| Glycémie au coucher + écart vs cible | CGM |
| Tendance / pente au moment du coucher ou de la correction | CGM |
| Dose de correction (si prise) | Injection rapide |
| IOB résiduel | Calcul (DIA) |
| Temps depuis le dernier repas | Repas |
| Dose de lente + temps entre correction et lente | Injection lente |
| Sport du jour (type/intensité/durée) + charge 7j | Sport |
| Glucides pris autour (collation + resucrage) | Repas + Resucrage |
Ces features alimentent l'affichage contextuel des lignes (chips) et la sheet détail de soirée — **pas** un modèle prédictif, et plus aucun mining depuis août 2026. Le Random Forest du cadrage initial avait déjà été écarté : une probabilité ou une dose recommandée sortie d'un modèle opaque contredirait la philosophie faits + transparence + dénominateurs, et frôlerait le conseil interdit.

---

---

## UI — Page fusionnée « Hypos au coucher » (validée 2026-07-12, implémentée)
B2 et B3 sont présentés dans **une seule section UI** « Hypos au coucher » (focus hypo — l'événement dangereux ; l'issue « insuffisant » de B3 reste visible au détail des soirs mais ne pilote pas la page). La page « Analyse du coucher » a 2 pills : « Tendance basale » (B1) et « Hypos au coucher » (B2+B3).

Structure de la page, purement rétrospective :

1. En-tête de la carte : nombre de soirs analysés + fenêtre (depuis le changement de dose, ou dose de lente actuelle). C'est le dénominateur commun des trois métriques qui suivent.
2. **Carte de métriques comptées** : trois faits, tous recomptables à la main depuis la liste des soirs — **hypos** (total), **dont avec rechute** (un resucrage correctif suivi d'une nouvelle hypo dans l'heure — sous-ensemble strict, jamais additionné au total), **hypos évitées** par un resucrage préventif, avec les glucides **médians** de ces prises (médiane et non moyenne : sur deux ou trois prises, une valeur extrême donnerait un chiffre que l'utilisateur n'a jamais pris). Le dénominateur commun (nombre de soirs analysés) et la fenêtre (depuis le changement de dose) sont rappelés en en-tête de la carte. Une métrique à 0 s'affiche en gris : c'est une bonne nouvelle, pas une alerte.
3. Liste « Soirs en hypo » (stables en compteur, « Voir tout » déplie la liste complète, triable par date ou par glycémie). Un soir « hypo évitée » y porte le constat « hypo évitée · resucrage préventif » en ambre — ni le rouge de l'hypo, ni le vert du soir calme.
4. Bouton « Comparer la glycémie de ce soir » → `SheetComparerCeSoir`  (critères détaillés plus bas).**Implémentation** : calculateur pur `CalculHyposCoucher.swift`  (fusion B2+B3, nonisolated/Sendable), vue `PageHyposCoucher.swift`  ; les anciens `TableauEndormissement`  / `TableauCorrections`  sont supprimés.**Retrait des « Situations observées » (août 2026).** Le mining de combinaisons de facteurs par énumération exhaustive a été supprimé, code et tests compris : à l'usage, un facteur isolé — sans mise en regard des autres analyses — ne disait rien d'actionnable, et la section alourdissait la page pour un signal qu'on ne savait pas exploiter. `CalculSituationsCoucher`  est devenu `CalculHyposCoucher`  et ne fait plus que la fusion B2+B3 ; les types `SituationCoucher`  , `FacteurCoucher`  et `TrancheCoucher`  n'existent plus. L'épinglage « ce soir » de `SheetComparerCeSoir`  , qui en dépendait, a disparu avec eux. Ne pas réintroduire ce mining sans un besoin démontré : la valeur est dans les faits comptés et la liste des soirs, pas dans une corrélation à quatre nuits.**Détection de la rechute.** La rechute (resucrage correctif suivi d'une nouvelle hypo < 60 min) n'existait qu'au niveau nuit dans B1 (`BilanHyposNuit.rechutes` ). `DetectionRechute`  la porte désormais au niveau du coucher, sur un recul de 6 h après l'événement (aligné sur la fenêtre de sur-correction de B3), et **délègue entièrement** à `CalculAnalyseBasale.bilanHypos`  : l'app doit avoir une seule définition du mot « rechute », deux définitions divergentes sur deux écrans seraient pires que pas de métrique. Branchée sur B2 (à partir de la lente) comme sur B3 (à partir de la correction). La fenêtre large ne crée pas de faux positifs : deux épisodes ne s'apparient que s'ils sont séparés de moins de 60 min et que le premier porte un resucrage correctif.
**Sheet réutilisable « Détail d'une soirée »** (`SheetDetailSoiree.swift` + `CalculDetailSoiree.swift`) : timeline des événements (repas, resucrage, correction, lente, hypo, réveil), courbe de glycémie Swift Charts (seuil hypo en pointillés, marqueurs d'événements — pas de mise en évidence de « fenêtre analysée » : retirée après revue, jugée trompeuse car ne recouvrait pas les hypos réelles), courbe d'aire IOB avec repère vertical à la première hypo, carte de constat B1 (réutilise l'analyse basale de la nuit), et carte « Contexte » (chips taille large, mêmes composants que la liste des soirs). Ouvrable depuis la liste des soirs et depuis les résultats de `SheetComparerCeSoir` (sheet dans sheet). Le resucrage y est un événement à part entière, avec son intention déclarée en sous-titre et son marqueur sur la courbe — l'ancienne heuristique « repas pris moins de 45 min après une hypo = resucrage » est supprimée, l'intention étant désormais saisie par l'utilisateur.

**Composant réutilisable** `**LigneSoirCoucher.swift**` : barre d'accent colorée en overlay (pas en HStack, pour éviter un bug de hauteur avec `FlowLayout`), glycémie + flèche de tendance en hero avec date en dessous, chips de contexte (`ChipContexte`/`ChipCharge`, SF Symbols, pas d'emoji) enroulés en `FlowLayout`, badge correction en indigo foncé, chip de charge d'activité en flamme colorée (`ChargeActivite.couleur`). Les chips supportent une taille compacte (liste) et large (sheet détail) via l'enum `TailleChip`.

**Filtre et tri de la liste des soirs** : filtre Hypos / Tous en `Picker` segmenté natif (hauteur, typographie et cible de tap du système, suit Dynamic Type), tri date / glycémie en bouton bordé affichant le critère actif. L'ancienne pastille d'icône de 26 pt était sous le minimum tapable iOS et n'indiquait pas le tri courant. Le bouton « Comparer à ce soir » est remonté sous la carte de métriques : en pied de liste, il pouvait se trouver à quatorze lignes de scroll.

**Chargement non-bloquant** : les 3 services d'analyse (B1/B2/B3) exposent un flag `enCalcul` ; la lecture du hub (`LecteurHub`) et l'assemblage pur tournent hors du thread principal, et un retour sur l'onglet ne recalcule que si les données ont changé (`MarqueurFraicheur`), ce qui élimine le lag à l'ouverture de l'onglet Analyses. Pendant le recalcul, le chevron de la carte `CarteAnalyseCoucher` est remplacé par un spinner (`ProgressView`) plutôt qu'une barre de progression déterministe (approche testée puis écartée).

### Critères de la recherche « Comparer à ce soir » (implémenté)
Saisie : la glycémie actuelle uniquement (clavier, gros chiffre) — c'est la seule donnée que l'app ne connaît pas (CGM ~3h de retard). Le reste du contexte est pré-rempli depuis le hub et proposé en **chips activables** — charge d'activité 7 jours, sport du jour et son type, IOB à l'instant — la dose de lente restant en affichage seul.

Corpus de recherche : 60 nuits glissantes (horizon aligné sur le cadrage B3), recalculées à la volée par le pipeline complet B1 → fusion B2+B3 avec fenêtre élargie (`RechercheCoucher.corpus`), SANS le reset au changement de dose de lente — la recherche compare à tout l'historique récent, toutes doses confondues, contrairement au tableau de la page qui ne montre que la fenêtre comparable. Calcul pur, instantané, jamais persisté.

Critères de similarité (V2, août 2026) — deux étages combinés en ET :

**Étage 1, la bande de glycémie** : |glycémie du soir passé − glycémie saisie| ≤ bande, réglable par slider de ±10 à ±30 mg/dL (pas de 5, défaut ±15). Résultats triés du plus proche au plus éloigné de la saisie, scindés « fini en hypo » / « resté stable » (stables tronqués à 3, dépliables).

**Étage 2, les critères de contexte** (`FiltreCoucher.swift`, pur et testé) : chips activables construites depuis le contexte réel de ce soir — _sport le jour_, _même type de séance_, _même charge 7 jours_, _insuline encore active_. Chaque critère est **ancré sur ce soir**, pas sur une valeur fixe : sans sport ce soir, la chip cherche les soirs **sans** sport, et le type de séance n'est proposé que si une séance a eu lieu. Les critères se combinent en ET, jamais en OU.

**Le compteur est ce qui rend le filtrage tenable.** Chaque chip affiche l'effectif qui **resterait** si elle était activée, calculé sur la bande courante et les critères déjà posés (`FiltreCoucher.compteSiAjoute`). L'utilisateur voit le coût d'un critère avant de le poser, et une chip qui viderait la liste est **désactivée** plutôt que de mener à un écran vide sans coupable identifiable. Sans ce compteur, filtrer sur ~60 nuits d'historique était une fausse bonne idée — c'était la raison du refus initial de tout filtrage (décision de juillet 2026, désormais levée).

**Ce qui reste hors critères** : la dose de lente (filtrer dessus reviendrait à retomber sur la fenêtre de dose du tableau de la page, alors que la recherche compare justement toutes doses confondues) — affichée en texte discret, pour mémoire. La tendance/flèche au coucher n'est pas encore un critère : l'app ne la connaît pas ce soir (retard CGM), il faudrait la saisir comme la glycémie — cadré, pas implémenté.

**Toujours pas de score de similarité pondéré** : opaque, et il inventerait de la précision sur un historique de cette taille. Filtres binaires explicites + compteurs : l'utilisateur voit exactement ce qu'il compare.

Navigation : chaque soir de résultat est tappable → sheet « Détail d'une soirée » (empilement de sheets). Garde-fou affiché, adapté à l'état : sans critère actif, « le contexte affiché sur chaque ligne n'est pas filtré — à toi de comparer » ; avec critères, un rappel que l'effectif a rétréci et qu'il faut lire les dénominateurs.

Évolutions possibles : **saisir la tendance** (flèche) à côté de la glycémie et en faire un critère — au coucher, 118 stable et 118 qui descend sont deux soirées sans rapport, et c'est la seule autre donnée que l'app ne peut pas connaître ; une **synthèse chiffrée** en tête des résultats (« 3 / 6 finis en hypo, 1 hypo évitée, 2 stables ») plutôt qu'une liste à scanner ; un **relâchement guidé** à zéro résultat (« sans _Course_ → 6 soirs », en un tap) ; élargir l'horizon au-delà de 60 nuits avec marquage des anciennes doses.

---

## À faire plus tard
- **Resucrage disproportionné** : détecter un resucrage qui fonctionne mais qui nécessite anormalement plus de glucides que la règle de base (~15 g) — signal d'hypo « collante » ou de sensibilité anormale. Cadré dans le doc B1, jamais implémenté.
- **Compression capteur** : filtrer les fausses hypos par compression (signature en V étroit, < 15–20 min), qui polluent aujourd'hui le compteur d'hypos comme des vraies.
---

---

---

## Dépendances & garde-fous
- **Dépend de B1** pour la préparation de données (segmentation, zones, IOB) et la catégorie de dérive zone 3, affichée dans la sheet détail de soirée.
- **Régulatoire — point sensible** : faits uniquement, jamais « faites Xu » ni de cible glucides. Garde-fou affiché dans l'UI. Les V4/V2 prédictives (« suggestion glucides pré-coucher », dose recommandée par modèle) ont été explicitement **supprimées/écartées** : c'est la ligne à ne pas franchir.
- **Charge d'activité, sport, glucides** : montrés comme co-occurrence/contexte, jamais comme cause affirmée.
- **Événements rares** : B3 (corrections) accumule lentement — seuils de fiabilité indicatifs : 15 corrections pour un premier aperçu, 30+ pour fiable. B2 ne se gate pas (remonte les faits dès qu'ils surviennent).
