# R1 — Réponse glycémique post-repas
>   Corrèle chaque repas au vrai CGM du hub pour produire un verdict factuel, apprend statistiquement le ratio insuline/glucides qui fonctionne le mieux par moment de la journée, et signale un écart factuel entre le ratio configuré et le ratio observé. Jamais une dose recommandée.  

**Statut** : 🟢 Implémenté (socle factuel + cœur ML + normalisation contexte + progression) · **Type** : statistique descriptive (pas de CreateML/Random Forest) · **Priorité** : ⭐⭐⭐⭐⭐ · 100% on-device
**Fichiers** : `Diaviz/services/derivation/AssembleurReponseRepas.swift`, `Diaviz/services/derivation/CalculRatioObserve.swift`, `Diaviz/services/derivation/CalculRepasARevoir.swift`, `Diaviz/services/derivation/CalculRepasIsoles.swift`, `Diaviz/services/hub/RepasService.swift`, `Diaviz/services/hub/AnalyseRatioService.swift` (exclusion des repas post-sport du mining), `Diaviz/services/InsightsService.swift`, `Diaviz/services/ContextesRepasRecentsService.swift`, `Diaviz/services/ReferentielContextesService.swift`, `Diaviz/services/ContexteNormaliseGenerator.swift`, `Diaviz/services/RepasARevoirMasquesService.swift`, `Diaviz/modeles/repas/Aliment.swift`, `Diaviz/modeles/repas/ContexteNormalise.swift`, `Diaviz/modeles/repas/RepasARevoir.swift`, `Diaviz/modeles/profil/DatesChangementRatio.swift`, `Diaviz/vues/accueil/CarteAnalyseRatio.swift` 

---

---

## Pourquoi
- Repas/insuline est le **cœur de l'app** dans le backlog ML (⭐⭐⭐⭐⭐) : après B1 (basale nocturne) et B2+B3 (coucher), R1 répond à la question la plus fréquente d'un DT1 sous stylo au quotidien — _« le ratio insuline/glucides est-il bon, à ce moment de la journée, pour ce genre de repas ? »_
- Sans corrélation au vrai CGM, l'utilisateur navigue à l'instinct : il sent qu'un repas « n'a pas marché » sans savoir objectivement si c'est le ratio de base, un facteur ponctuel (sport, stress, repas gras), ou juste le hasard d'un aliment mal estimé.
- **Précédent réglementaire fort** : un Random Forest avait été envisagé pour B3 (corrections du soir) puis **abandonné** — jugé trop opaque, trop proche du conseil médical. R1 suit la même philosophie dès le départ : **statistique descriptive**, jamais un modèle entraîné, jamais une dose recommandée. Chaque chiffre affiché doit rester recomptable à la main depuis les repas listés.
- Formulations toujours **factuelles** avec dénominateurs bruts (« vos repas à ce ratio ont X % de bons résultats, n/n »), jamais thérapeutiques (« utilise ce ratio »).
---

## Quoi (ce que l'app remonte)
### 1. Réponse glycémique par repas
- Chaque repas récent (< 45 jours) reçoit un verdict factuel — **bon / moyen / mauvais / indéterminé** — à partir de la vraie courbe CGM du hub sur la fenêtre **T-1h → T+4h**.
- États honnêtes quand le verdict n'est pas encore calculable : **en attente** (fenêtre CGM pas encore remplie), **données manquantes** (capteur déconnecté, trou de données), **sans injection** (repas non bolusé — pas d'analyse pertinente).
- Affiché en couleur dans le journal (mini-courbe), le graphe de la journée, et le détail du repas.
### 2. Insights de saisie réels
- **IOB** (insuline rapide encore active), **sport détecté** dans les 3h précédant le repas, **validation de la dose saisie** vs le ratio _configuré_ dans le profil (matin/midi/soir ou ratio unique selon le mode) — tous dérivés du hub, plus aucun mock.
### 3. Mining du ratio observé (le cœur ML)
- Bucketise les repas exploitables selon leur **ratio effectif** (glucides ÷ dose donnée), comparé au ratio configuré en grammes par unité — trois tranches : dose nettement plus faible, proche du ratio configuré, dose nettement plus élevée — et lit le **taux de bons verdicts** par tranche, avec dénominateurs.
- Détecte un **écart significatif** entre le ratio configuré et un ratio mieux observé, affiché comme une alerte factuelle dans la carte « Validation ratio » de la saisie.
- **Les repas ajustés sont exclus du mining**, pas minés à part comme dans une version antérieure de cette page — voir « Ajustements exclus du mining » dans Comment pour le raisonnement (comparer une dose volontairement déviée au ratio de base ne mesure rien). Ils restent **toujours affichés** sur l'accueil dans « Repas à revoir », badge(s) d'ajustement, sans seuil.
- **Seul garde-fou de volume :** `effectifMinimalBucket = 5`  par tranche. Une tranche de moins de 5 repas est ignorée ; un groupe produit ses buckets dès qu'au moins une tranche atteint 5 repas. L'ancien seuil de 30 repas par groupe était largement redondant avec ce garde-fou par tranche (c'est la tranche, non le groupe, qui porte le risque de bruit), cachait pendant des semaines des dénominateurs pourtant honnêtes (« 4 bons sur 6 ») et repartait silencieusement à zéro à chaque changement de ratio.
- **Verdict visible par moment :** la carte accueil « Analyse du ratio » (`CarteAnalyseRatio`  ) affiche désormais un verdict plutôt qu'une progression : « écart détecté », « ratio confirmé », un taux brut avec « peu de recul », « Ratio changé le , N repas depuis » ou « Pas encore de repas analysé » selon les données disponibles — voir « Verdict par moment » dans Comment.
### 4. « Repas à revoir » (accueil)
- Regroupe les repas **récurrents** (même composition) dont la **dernière** occurrence est sortie de cible. Montre le nuage des courbes passées (dispersion) + la dernière courbe en couleur de sévérité, avec badges factuels (moment de la journée, ajustements présents).
- **Aucun seuil global** (contrairement au mining ci-dessus) : dès qu'un même repas récurrent a mal tourné la dernière fois, c'est remonté — fait direct, pas une inférence statistique sur l'ensemble des repas.**⚠️ Deux conditions indépendantes, à ne pas confondre.** La carte apparaît si — et seulement si — les deux sont vraies :
1. la **dernière** occurrence du groupe a un verdict `mauvais`  ;
2. le groupe compte au moins **N occurrences au total**, _tous verdicts confondus_.`N`  est réglable par l'utilisateur de 1 à 5 (`ProfilUtilisateur.preferencesAvancees.occurrencesMinimalesRepasARevoir` , défaut 2, section « Repas à revoir » du profil). À 1, la récurrence est de fait désactivée : tout repas hors cible remonte dès la première fois.
Ce seuil compte donc des **répétitions, pas des échecs**. Un plat mangé 3 fois dont une seule a mal tourné remonte exactement comme un plat raté 3 fois sur 3 — c'était le principal malentendu de lecture de cette carte, corrigé côté affichage (voir ci-dessous), pas côté règle.

- **Compteur d'échecs** : la carte affiche « N fois sur M hors cible » sous le verdict (`RepasARevoir.libelleRecurrenceEchecs`  ). En rouge lorsque **toutes** les occurrences sont hors cible (`echecSystematique`  ) — le cas qui justifie de remettre le ratio en question, par opposition à un raté isolé.
- **Courbes passées teintées selon leur verdict** : celles hors cible passent en rouge atténué (trait 1,5pt) au lieu du gris commun. Un nuage gris uniforme suggérait implicitement « ça marche d'habitude », y compris quand c'était faux — une occurrence passée en hypo à 45 se dessinait exactement comme une occurrence parfaite.
- **Un seul constat affiché**, toujours celui de la **dernière** occurrence (« Pic 186 · après 3h55 »). Les occurrences passées ne produisent pas de constat propre, quel que soit leur verdict. À l'intérieur d'une même occurrence, l'hypo prime sur le pic quand les deux coexistent — même règle que `RaisonMauvaisVerdict`  .
- **Masquage par appui long** (`RepasARevoirMasquesService`  , `Set<UUID>`  en UserDefaults) : la clé est `RepasARevoir.idRepasSource`  , l'id du **vrai** `**Repas**`  ayant motivé la carte — jamais la signature du groupe. Si le plat se reproduit avec un nouveau mauvais résultat, le « dernier » devient un nouveau `Repas`  (nouvel id, absent du set masqué) et la carte réapparaît d'elle-même, sans logique dédiée. Masquer fait taire l'alerte courante, jamais le plat pour toujours. Purge globale depuis le profil.
### 5. Repas isolés (contexte libre et/ou ajustement) — accueil
- Un repas **isolé**, portant un **contexte libre** (« prise de la voiture »…) et/ou un **ajustement intentionnel** (sport récent, glycémie basse avant repas…), dont le verdict est mauvais, remonte seul dans « Repas à revoir » — pas de recherche de récurrence, pas de nuage de courbes passées — avec sa vraie courbe CGM et l'événement affiché tel quel. **Aucun seuil de données** : ce n'est pas une inférence statistique, juste un fait montré. Un repas avec les deux à la fois affiche les deux blocs de badges sur la même carte.
- Le badge de contexte utilise le libellé **normalisé** (ex. « 🚘 Voiture ») dès qu'il est résolu (voir « Normalisation LLM du contexte libre » dans Comment) ; sinon retombe sur le texte brut tapé par l'utilisateur. Le(s) badge(s) d'ajustement affichent la raison (« Sport récent · Course à pied »…).
### 6. Mode dose globale (saisie)
- Une seule dose pour tout le repas plutôt qu'une ventilation aliment par aliment, pour les cas où les quantités sont connues d'avance et où l'app donne déjà le total de glucides.
### 7. Flag resucrage sur un aliment
- ~~Déclaration manuelle qu'un aliment a été pris pour traiter une hypoglycémie~~ — retirée le 2026-11-13 : doublon de la page Resucrage, à moitié prise en compte. Plus proposée à la saisie ni lue par aucune analyse ; le champ reste stocké (iCloud ne permet pas de le retirer proprement).
### 8. Comparaison dose/verdict avant-après changement de ratio
- Dans `SheetEcartRatio`  , chaque section (moment de la journée) dont le ratio a déjà changé au moins une fois affiche désormais un badge à côté de son titre : date du dernier changement et nombre total de repas depuis. Un bloc juste en dessous compare, avant/après cette date, la dose moyenne appliquée et le taux de bons verdicts (réponse glycémique) dans les 3h suivant l'injection.
- Le badge est toujours affiché dès qu'un changement existe, même sous le seuil de comparaison. Le bloc de comparaison lui-même n'apparaît que si au moins 5 repas ont eu lieu depuis le changement (`CalculDoseRatioChangement.effectifMinimalComparaison`  ) ; en dessous, un état « Pas encore comparable » est affiché à la place, avec le nombre de repas manquant.
- Réutilise la même matière première que le mining (verdict persisté par repas), lue sous un autre axe : fenêtre temporelle (avant/après une date) plutôt que tranche d'écart de dose. Contrairement au mining principal (`EntreeRatioRepas`  , qui exclut déjà tout ce qui précède un changement de ratio car il a besoin du ratio configuré actuel pour calculer une dose suggérée), ce calculateur travaille sur tout l'historique de repas exploitable, sans cette contrainte : il n'a besoin que de la dose appliquée et du verdict, pas d'une dose suggérée.
---

## Quand (à quel moment chaque calcul tourne)
Aucune tâche de fond dédiée (pas de `BGProcessingTask` pour R1, contrairement au re-entraînement ML évoqué dans le cadrage global) — tout tourne en synchrone, déclenché par des événements précis de l'app :

### Verdict par repas (`AssembleurReponseRepas` via `RepasService`)
- Recalculé à **chaque mutation du hub** : `RepasService.recharger()`  tourne après chaque lecture/écriture (ajout, édition, suppression d'un repas), et repose l'`EtatAnalyse`  sur tous les repas récents.
- Rappelé explicitement **une fois de plus au démarrage de l'app**, juste après la synchronisation HealthKit (`AppTabVues.task`  → `repasService.rafraichirAnalyses()`  ) — au tout premier chargement le CGM n'est pas encore synchronisé, donc sans ce second appel tous les repas resteraient marqués « en attente » jusqu'au relancement suivant.
- **Pas de mise à jour en continu** pendant que l'app reste ouverte en arrière-plan : si de nouvelles glycémies arrivent (HealthKit background delivery) sans mutation de repas ni redémarrage, le verdict d'un repas qui vient de passer en fenêtre complète n'est reflété qu'au prochain de ces deux déclencheurs. Limite connue, assumée pour l'instant.
- Le verdict + ratio effectif sont **persistés** dès qu'ils deviennent `.disponible`  — un repas déjà figé ne redéclenche pas d'écriture superflue (comparaison avant `save()`  ).
### Mining du ratio observé (`CalculRatioObserve` via `AnalyseRatioService`)
- **Jamais recalculé à chaque frappe de saisie.** Le cache mémoire (`AnalyseRatioService.analyse`  ) est reconstruit à la même cadence que le verdict par repas ci-dessus : au démarrage de l'app, après la synchronisation HealthKit, et après chaque repas validé dans `RepasSheet`  /`AjouterRepasVue`  .
- Pendant la saisie d'un repas, la carte « Validation ratio » ne fait qu'un **lookup instantané** (O(1)) dans ce cache déjà calculé — aucun recalcul du mining lui-même à ce moment-là, seulement la comparaison de la dose en cours de saisie au résultat existant.
- Volume trivial (quelques milliers de repas au grand maximum sur plusieurs années) : le recalcul complet lui-même, quand il a lieu, reste quasi instantané sur le thread principal — pas besoin de `Task.detached`  .
- Recalculé aussi après tout changement de ratio dans Profil (`SectionRatios`  ) — la date de changement stampée y déclenche le même cycle, la progression et le mining reflètent immédiatement le nouveau périmètre de données éligibles.
### Cartes accueil (« Repas à revoir » / « Analyse du ratio »)
- Calculées comme des propriétés dérivées de `AccueilVue`  (ou lues directement depuis l'environnement pour `CarteAnalyseRatio`  ), réévaluées à chaque rendu de la vue à partir de `repasService.repas`  et `analyseRatioService.analyse`  déjà en mémoire — pas de déclenchement séparé, elles suivent automatiquement le rythme du verdict par repas et du mining ci-dessus.
- Transition douce (fondu + glissement) à l'apparition, pour absorber visuellement le court délai entre l'affichage de l'accueil et la fin du premier chargement du hub au démarrage.
### Normalisation du contexte libre (`ReferentielContextesService` via `RepasService`)
- **Temps réel (frappe)** : `SectionContexteRepas`  interroge `ReferentielContextesService.suggestions(pour:)`  à chaque frappe — matching local instantané, **aucun appel Foundation Models** à ce moment.
- **Après enregistrement du repas** : `RepasService.enregistrerDepuisSaisie`  lance une `Task`  non bloquante juste après `enregistrer(nouveau)`  — la sheet peut déjà être fermée. Cette tâche appelle `ReferentielContextesService.resoudre(texte:)`  , qui retente d'abord le matching local, puis appelle Foundation Models seulement si rien n'a matché. Le résultat est écrit sur `Repas.contexteNormalise`  et sauvegardé.
- Pas de garantie de délai : dépend de la disponibilité du modèle on-device et du temps de génération, généralement quelques secondes. Aucun indicateur de chargement dans l'UI — le badge affiche le texte brut jusqu'à la mise à jour automatique (SwiftData notifie la vue dès que le champ change).
---

## Comment
### Fenêtre d'observation et couverture
- Fenêtre : **T-1h à T+4h** autour de l'heure du repas (`AssembleurReponseRepas.debutFenetre`  /`finFenetre`  ).
- Résolution CGM attendue : 1 mesure / 5 min (Dexcom).
- **Couverture minimale pour une analyse fiable : 80 %** de la fenêtre post-repas. En dessous → `enAttente`  ou `donneesManquantes`  selon le délai.
- **Délai de capture CGM : 3h** (délai réel Dexcom UE). La fenêtre est réputée capturable à `T+4h + 3h`  . Avant cette échéance et couverture insuffisante → `enAttente(minutesRestantes:)`  . Après, et toujours insuffisante → `donneesManquantes`  .
- Repas analysés pour la courbe : uniquement ceux de **moins de 45 jours** (backfill Dexcom borné à 7 jours côté ingestion, inutile de recalculer au-delà).
### Règle de verdict — « excursion + retour », cible 70–180 mg/dL
Calculée sur la seule portion post-repas (T0 → T+4h) :

- **mauvais** si : hypoglycémie observée sur **toute la fenêtre T0 → T+4h** (tout point sous `SeuilsGlycemiques.hypoglycemie`  , 70 mg/dL par défaut mais réglable dans le profil) ; OU pic ≥ 250 mg/dL ; OU le pic dépasse 180 et la glycémie n'est jamais redescendue ≤ 180 dans la fenêtre (excursion jamais refermée). Les 3h de délai de capture CGM Dexcom sont une notion distincte : elles ne limitent pas la fenêtre de détection de l'hypoglycémie.
- **bon** si aucune des conditions ci-dessus n'est vraie, ET : pic resté ≤ 180 mg/dL (pas d'excursion) ; OU retour ≤ 180 mg/dL dans les 2h suivant l'heure du repas (T0), avec pic < 220 mg/dL (retour rapide, couvre les départs en hyper suivis d'une bonne correction). Pour un repas au pic tardif, cette fenêtre de 2h comptée depuis T0 est donc plus stricte qu'une fenêtre de 2h comptée depuis le pic lui-même.
- **moyen** : tous les autres cas.
- **indéterminé** : pas de verdict calculable (repli défensif, ne devrait pas arriver si `.disponible`  ). Cette règle remplace l'ancienne logique du seul pic (ignorait le temps de retour en cible) — un repas pris à 220 mg/dL qui redescend proprement à 130 en 1h30 est un **bon** résultat, pas un mauvais.Décision actée le 2026-08-10 : le retour est volontairement compté depuis T0. La documentation antérieure (« 2h après le pic ») était en avance sur le code ; elle est corrigée pour suivre le comportement implémenté, et non l'inverse.
### Persistance du verdict (pour le mining + un futur LLM)
- `Repas`  porte 3 champs **stockés** (non-`@Transient`  ) : `doseCorrection`  (dose de correction d'hyperglycémie, distincte de la dose couvrant les glucides), `verdictPersiste`  , `ratioEffectifPersiste`  — écrits par `RepasService.annoterReponsesGlycemiques()`  dès que le verdict devient `.disponible`  .
- `AssembleurReponseRepas`  (l'algorithme du verdict lui-même) n'est **pas modifié** — seul l'endroit où son résultat est conservé change.
- Objectif : rendre la base de repas interrogeable (par un futur LLM conversationnel) sans dépendre du CGM en mémoire.
- **Limite connue** : les repas enregistrés avant l'ajout de `doseCorrection`  restent un proxy — leur dose totale peut inclure une correction non séparable rétrospectivement.
### Cause d'un verdict mauvais
`RaisonMauvaisVerdict` (`hypoglycemie` / `hyperglycemie`) est défini dans `RepasGraph.swift`, à côté de `VerdictGlycemique` mais volontairement séparé de lui. Le verdict est déjà persisté (`Repas.verdictPersiste`, export JSON) et lu par une quinzaine de fichiers ; y ajouter un quatrième cas aurait imposé une migration et une recompilation en cascade. Un champ distinct se greffe sans rien casser.

- Chaîne complète : `AssembleurReponseRepas`  calcule la raison lorsqu’un verdict est `.mauvais`  → `ReponseGlycemique.raisonMauvais`  → `Repas.raisonMauvaisPersistee`  → `ArchiveDonneesService`  → `EntreeRatioRepas.raisonMauvais`  → couleur du point dans `GraphiqueZonesRatio`  .
- L’hypoglycémie prime lorsqu’elle coexiste avec un pic : c’est l’événement le plus lourd et souvent la cause du pic qui suit, via le resucrage.
- `raisonMauvaisPersistee`  est optionnel, sans contrainte et compatible CloudKit ; aucune migration n’est requise. L’archive exporte ce champ de façon optionnelle avec une valeur par défaut, de sorte que les archives antérieures restent réimportables.
- Dans le graphique, une hypoglycémie est rouge ; un mauvais verdict par hyperglycémie est orange (pic modéré en jaune). Lorsqu’aucune raison n’est disponible, le point retombe sur la couleur générique du verdict.
### Mining du ratio observé (`CalculRatioObserve.swift`)
- Calculateur pur (`nonisolated enum`  , `Sendable`  ), même famille que `CalculSituationsCoucher`  (B2+B3) : énumération exhaustive, dénominateurs bruts, seuils stricts.
- Groupe = `SectionRepas?`  (moment de la journée, `nil`  en mode ratio unique) — un seul type de groupe désormais, les ajustements n'en produisent plus (voir sous-section suivante).
- `ObservationRatioSection`  porte un champ `effectif: Int`  **toujours peuplé** : c'est le dénominateur affiché du nombre de repas exploitables dans ce groupe. Les `buckets`  sont produits dès qu'au moins une tranche contient `effectifMinimalBucket`  repas ; les tranches sous ce minimum sont ignorées.
- Constantes : `effectifMinimalBucket = 5`  (repas par tranche), `ecartMinimal = 0.25`  (points de taux), `toleranceGrammesParUnite = 1.0`  (g/u autour du ratio configuré).
- `tranche(...)`  reçoit les glucides en plus des deux doses et compare le **ratio effectif** (`glucides ÷ dose donnée`  ) au ratio configuré. La tolérance est donc directement lisible dans l'unité des réglages : autour de 1u/12g, la zone proche couvre 1u/11g à 1u/13g. Le sens est inverse de celui de l'insuline : un ratio effectif plus élevé signifie moins d'insuline et relève de `.doseNettementFaible`  ; un ratio effectif plus faible signifie davantage d'insuline et relève de `.doseNettementElevee`  .
- Le mining tourne sur **tout l'historique persisté depuis le dernier changement de ratio du groupe concerné** (voir « Traçage des changements de ratio » ci-dessous) — plus de fenêtre glissante au sens strict, mais plus non plus la limite historique « repas anciens comparés au ratio actuel » : un changement de ratio referme la fenêtre de comparaison de son groupe.
- `InsightsService.validation(...)`  affiche l'écart du groupe (moment) du repas en cours de saisie.
### Graphique en gélules — un moment à la fois (2026-10-09)
Remplace le nuage de points (`GraphiqueZonesRatio`, supprimé) : les points se chevauchaient avec le temps, et voir chaque repas un par un n'apportait rien. Choisi parmi plusieurs maquettes.

- **Une gélule par ratio réellement appliqué**, arrondi au g/u (`ColonneRatio.colonnes`). Hauteur = nombre de repas, remplissage de bas en haut : en cible (vert), pic modéré (jaune), hyper (orange), hypo (rouge) — même distinction de cause qu'avant. Les g/u sans repas entre le plus petit et le plus grand ratio observé (± 1) restent visibles en petit point gris : un trou est une information.
- Axe inversé comme avant : « moins d'insuline » à gauche. Ratio configuré entouré.
- **Aucun chiffre sur les gélules.** Toucher ou glisser sur une gélule met à jour le score en tête de page (« À 1u/9g · 67 % · en cible · 2 sur 3 repas »), avec retour haptique ; sans toucher, le score porte sur le ratio actuel.
- Libellé en gras = gélule dont le score est affiché. Changer de moment se fait sans animation (graphique reconstruit).
- **Un seul moment affiché** (plus de pile de sections), ordre chronologique conservé — voir « Mise en page » ci-dessus pour le sélecteur.
- Sous le graphique : la comparaison des 3 zones (± 1 g/u) avec « meilleur taux » / « ratio confirmé », seulement quand elle est possible (plus de mention « X repas, Y au plus dans une zone ») ; le bloc « depuis le changement de ratio ».
- Carte « repas écartés » du moment : total, décompte par raison (fenêtre, ajusté, contexte libre, ratio sport, exclu à la main), et total général.

### Mise en page de la page de détail (révisée 2026-10-19)
Retour arrière sur le style « 100 % Liquid Glass » : la page doit ressembler aux autres pages d'analyse.
- Fond gris système, cartes standard (`surfaceCarte`), carte de présentation `EnTeteAnalyse` en haut. Plus de halo teinté, plus de verre sur les cartes ni sur les gélules.
- Vouvoiement, titres de section : Moment de la journée, Résultat, Comparaison, Depuis le …, Repas écartés. Une seule ligne de pied de page.
- **Moments** : pastilles à icône (mêmes icônes et teintes que la carte d'accueil) défilant horizontalement, sous l'en-tête ; les 4 moments toujours présents, grisés sans repas (message « Aucun repas depuis le changement de ratio… » ou « Aucun repas analysé pour ce moment. ») ; la pastille choisie est centrée à l'arrivée et au choix. La barre flottante en bas a été abandonnée (peu visible).
- Sélecteur de période à libellé fixe **« Ratios actuels | Tout »**, sous les pastilles ; la date du changement est dans le titre « Depuis le … ». La bascule garde le moment affiché.
- Carte Résultat : « Déjeuner · Ratio actuel 1u/9g », score, gélules. Gélule sélectionnée : liseré blanc épais + ombre ; ratio actuel : contour pointillé.
- Couleurs des résultats (convention des capteurs) : en cible vert, pic modéré **jaune**, hyper **orange**, hypo rouge. Le brun puis le violet ont été essayés et rejetés.

### Plage du graphique bornée autour du ratio (2026-10-19)
Avec le mode avancé, des ratios extrêmes (corrections…) donnaient 20 gélules et plus. Une gélule par g/u de **ratio −3 à ratio +3** ; au-delà, deux gélules d'extrémité « ≥ Xg » / « ≤ Xg » regroupent le reste (absentes si vides). Au toucher : « 1u/14g et plus ». Si la largeur manque encore, le graphique défile (sélection au toucher), centré sur le ratio actuel. La liste « Par ratio appliqué » des repas écartés regroupe les extrémités de la même façon (même clé que la gélule, donc surlignée au toucher).

### Mode avancé — raisons d'exclusion désactivables (2026-10-19)
Section « Raisons d'exclusion » en bas de la page de détail : une pastille par raison de fenêtre **modifiable** — correction, autre repas dans les 4 h, insuline encore active, resucrage, sport. Pastille allumée (défaut) = règle appliquée ; éteinte = ses repas reviennent dans les gélules et la comparaison (`AnalyseRatioService.analyser(raisonsIgnorees:toutHistorique:)`, qui rejoue `mapperEntrees` sur les entrées du dernier calcul).

- **Jamais modifiables** : ajusté, contexte libre, ratio sport en vigueur, exclu à la main — la dose y est volontairement déviée, ou l'exclusion est un choix explicite.
- **L'accueil reste strict** : carte « Analyse des ratios » et insight d'écart ne lisent que l'analyse complète des exclusions.
- **Toujours visible** : bandeau orange en tête (« Mode avancé · N repas réintégrés », raisons incluses, bouton Réinitialiser) et mention sous la comparaison.
- **Jamais mémorisé** : chaque ouverture de la page repart en mode strict.
- Motivation : les corrections au repas sont fréquentes, et le mode strict peut écarter la majorité des repas d'un moment. Comparer une gélule avec et sans corrections dit, sur ses propres chiffres, si la règle peut être assouplie.

### Vue « Depuis le changement » / « Tout » (2026-10-09)
Un changement de ratio n'efface rien : il pose une date, et le mining ignore les repas antérieurs. Plutôt qu'un choix figé au moment du changement (alerte envisagée puis abandonnée), la page de détail propose un sélecteur **« Ratios actuels | Tout »**, affiché seulement si le ratio du moment a déjà changé.

- `AnalyseRatioService` calcule les deux : `analyse` / `repartitions` (filtre de date, inchangé) et `analyseComplete` / `repartitionsCompletes` (`mapperEntrees(ignorerChangementRatio: true)`). Toutes les autres exclusions s'appliquent pareil.
- Les gélules restent justes dans les deux vues : elles rangent chaque repas par ratio **appliqué**, pas par ratio réglé à l'époque. Dans « Tout », les repas d'une ancienne période à un ratio donné retombent d'eux-mêmes dans la gélule de ce ratio.
- La comparaison des 3 zones (centre = ratio actuel) compte aussi en vue « Tout », avec la mention « Inclut des repas faits avec un autre réglage de ratio ».
- **L'accueil (carte « Analyse des ratios », insight d'écart) ne lit que la vue filtrée** : un verdict ne se confirme pas avec des repas faits sous un autre réglage.
- Sans aucun repas depuis le changement, la page s'ouvre directement sur « Tout » plutôt que vide.
- La mention « 45 derniers jours » en pied de page était fausse (le mining lit le verdict persisté, sans borne de date) : retirée.

### Délai entre deux changements de ratio (2026-11-08)
**Question de l'écran :** puis-je changer ce ratio, ou manque-t-il encore du recul ?

**Besoin.** Chaque changement fait repartir l'analyse du moment de zéro. Des changements trop rapprochés empêchent donc tout constat sur le réglage en cours.

**Page Ratios (Profil), ratios glucides / insuline :**

- Chaque ligne affiche la valeur, puis en petit la date du dernier changement et le nombre de repas enregistrés sur ce moment depuis cette date (« Depuis le 3 nov. · 3 repas »). Un ratio jamais modifié affiche « Jamais modifié · N repas », tous repas du moment confondus. Le moment d'un repas suit le choix manuel s'il existe ; la nuit compte avec le dîner.
- Toucher une ligne ouvre une feuille, et la valeur n'est appliquée qu'à « Enregistrer » : passer de 10 à 12 fait un seul changement.
- Un ratio est verrouillé jusqu'à 5 repas enregistrés sur ce moment **ou** jusqu'au 14e jour après son dernier changement, selon ce qui arrive en premier (`CalculVerrouRatio`). Le délai de 14 jours évite un blocage sans fin sur un moment rare (goûter).
- Un ratio verrouillé se repère à un cadenas : ici l'icône dit un blocage, pas un critère non rempli. Sa feuille indique ce qu'il reste : « Modifiable après 2 repas de plus, ou le 17 nov. »
- « Modifier quand même », avec confirmation, reste possible depuis la feuille (ratio changé par le médecin) : sans cela, le réglage de l'app pourrait s'écarter du ratio réellement suivi.
- La première saisie reste toujours libre : elle ne constitue pas un changement.
- La bascule Unique / Par moment efface tous les ratios : elle est refusée tant qu'un ratio est verrouillé, sans sortie de secours.
- Ratios de correction et de sport : hors périmètre, aucune date de changement n'est enregistrée pour eux.

### Comparaison avant/après changement de ratio (`CalculDoseRatioChangement.swift`)
- Nouveau calculateur pur (`nonisolated enum`  , même famille que `CalculRatioObserve`  ) dans `Diaviz/services/derivation/CalculDoseRatioChangement.swift`  . Son entrée `EntreeDoseChangement`  porte l'heure, la dose appliquée et le verdict ; sa sortie `ComparaisonChangementRatio`  porte la date de changement, les statistiques « avant » optionnelles (`nil`  si aucun repas ne précède le changement) et les statistiques « après ». `effectifMinimalComparaison = 5`  : sous ce seuil de repas après le changement, `comparer(entrees:dateChangement:)`  retourne `nil`  .
- `AnalyseRatioService`  expose désormais `apercusChangementRatio: [SectionRepas?: ApercuChangementRatio]`  , reconstruit à chaque `recalculer(depuis:)`  , à la même cadence que le mining principal : démarrage, synchronisation HealthKit et chaque repas validé. Un mapping dédié (`mapperEntreesDoseChangement`  ) est volontairement dupliqué du mapping du mining principal : mêmes exclusions (pause, contexte libre, ajustement, verdict indéterminé, dose nulle), mais aucune dose suggérée calculée ni borne par date. Les deux mappers peuvent ainsi diverger indépendamment.
- `ApercuChangementRatio`  porte la date de changement, l'effectif total depuis et la comparaison optionnelle. Il alimente à la fois le badge, toujours visible dès qu'un changement existe, et le bloc de comparaison dans `SheetEcartRatio`  , affiché seulement lorsque la comparaison est non `nil`  .
- Couvert par `CalculDoseRatioChangementTests.swift`  : garde-fou d'effectif, bornes temporelles et calcul des moyennes.
### Ajustements intentionnels persistés
- `RaisonAjustement`  /`Ajustement`  (`AjustementSheet.swift`  ) sont `Codable`  , persistés sur `Repas.ajustements`  . `Ajustement.typeSportDetecte`  capture automatiquement le type de sport détecté (`InsightsService.sportRecent`  ) quand la raison est « sport récent ».
- `Ajustement.valeur`  est un **écart signé qui s'ajoute à la dose de base**, pas un delta déjà inclus dedans : `RepasService.enregistrerDepuisSaisie`  persiste la dose de base (`doseGlobale`  ou la ventilation par aliment), les ajustements et la correction partant chacun dans leur propre champ. D'où `Repas.totalInjecte = max(0, totalInsuline + totalAjustements + doseCorrection)`  , même formule que `RepasSheet.totalInjecte`  à la saisie. Le journal ventile ces termes dans une colonne alignée qui se vérifie de haut en bas (`RecapDosesRepas`  ).
- Pas de mining par type de sport spécifique (musculation vs course à pied) dans l'état actuel — ce sera le vrai **R2** une fois **S1** (réponse glycémique sport) fait.
### Repas post-sport écartés du mining
Un déséquilibre existait entre la saisie et le mining. À la saisie, `InsightsService.contexte(...)` résout le sport avant la validation : quand une séance récente a un ratio post-sport configuré, c'est **ce** ratio qui fait foi pour juger la dose, prioritaire sur le ratio du moment. Le mining, lui, calculait toujours sa dose suggérée avec `InsightsService.ratioConfigure(section:)`, c'est-à-dire le ratio du moment de la journée. Un repas post-sport correctement dosé selon le ratio sport était donc comparé au mauvais dénominateur et classé comme un écart — il alimentait un faux constat du type « ton ratio du midi est trop fort ». Le biais était silencieux : rien ne le signalait à l'écran.

Précision importante : l'ajustement manuel (`Repas.ajustements`) ne protégeait pas de ce biais, parce qu'il n'est jamais posé automatiquement. La détection du sport ne fait que **pré-remplir** la raison et le type dans la sheet d'ajustement (`RepasSheet`) ; sans validation explicite de l'utilisateur, aucun ajustement n'est enregistré et le repas entrait dans le mining.

Correctif : `AnalyseRatioService.mapperEntrees` écarte désormais tout repas pour lequel un ratio post-sport était en vigueur, au même titre qu'un ajustement manuel. La condition est double — une séance terminée dans la fenêtre d'effet configurée (`RatiosSport.fenetreEffetHeures`, séance encore en cours incluse, `dateFin` comme référence puisqu'elle réintègre les pauses) **et** un ratio renseigné pour ce type de sport. Les deux comptent : sans ratio configuré pour ce sport, `InsightsService` laisse la main au ratio du moment à la saisie, donc le repas reste légitimement comparable et ne doit pas être écarté.

L'exclusion est comptée dans `RepartitionRepasMoment.ratioSportEnVigueur`, donc visible dans la ventilation plutôt que silencieuse.

Les séances sont **injectées** et non fetchées dans le service : `recalculer(depuis:activites:)` reste l'entrée pure (contrôlable en test), et une variante de confort `recalculer(depuis:contexte:)` fait le fetch pour les vues appelantes. `AnalyseRatioService` reste ainsi sans `ModelContext` propre.

### Repas pollués par leur fenêtre — exclus du mining (2026-10-09)
**Constat.** Le verdict d'un repas se lit sur sa courbe de T−1 h à T+4 h, sans savoir ce qui s'y passe d'autre. Deux repas à 2 h d'écart étaient tous les deux gardés : le pic du goûter tombait dans la fenêtre du déjeuner (déjeuner bien dosé jugé « pic élevé »), et le goûter démarrait avec l'insuline du déjeuner encore active (hypo d'empilement attribuée à son ratio). Un point rouge pouvait donc vouloir dire « ratio inadapté » comme « repas gêné par son voisin » — un résultat d'apparence solide qui ne l'est pas.

**Décision : exclusion la plus restrictive possible.** Un repas ne compte pour juger un ratio que si sa courbe ne mesure **que** lui. `CalculExclusionsFenetre.raisons(...)` (pur, `Diaviz/services/derivation/`) retourne **toutes** les raisons qui s'appliquent, pas seulement la première. Fenêtre = celle du verdict, [T−1 h, T+4 h] (`AssembleurReponseRepas.debutFenetre` / `finFenetre`).

| Raison (`RaisonExclusionFenetre`) | Règle |
| ----- | ----- |
| `autreRepas` | Un autre repas dans [T−1 h, T+4 h], quelle que soit sa quantité de glucides, avec ou sans insuline |
| `insulineActive` | IOB ≥ 0,5 u au début du repas, calculé sur les injections rapides **antérieures**, hors bolus rattaché à ce repas (pré-bolus) — `IOBCalculateur`, DIA et pic du profil |
| `correction` | Correction saisie **avec** le repas (`doseCorrection > 0`) ou injection de correction dans la fenêtre |
| `resucrage` | Resucrage dans la fenêtre |
| `sport` | Séance qui chevauche la fenêtre (en plus de l'exclusion du ratio post-sport ci-dessus) |

**Correction faite avec le repas : exclue aussi.** Débattu : la dose de correction est déjà retirée de la dose couvrante, et son but est de ramener en cible. Mais le repas démarre haut — le pic monte plus haut même à ratio juste, ce qui pousse vers « moyen » / « mauvais » — et un échec ne peut plus être attribué entre ratio et facteur de correction. Décision : exclus comme les autres, sans affichage spécifique.

**Seuil d'insuline active : 0,5 u.** Plus petit pas d'un stylo demi-unité, ≈ 5 g de glucides à 1u/10g, donc sous l'erreur courante d'estimation des glucides. Plus bas, on écarterait sur la queue du modèle IOB, qui dépend surtout de la DIA saisie. Registre : « Paramètres à calibrer ».

**Règle commune R1 / C1 (2026-10-20).** Toutes les exclusions d'un repas passent par une seule règle, `CalculEligibiliteRepas.evaluer` : exclu à la main, contexte libre, ajustement (une raison de base au plus, dans cet ordre), ratio sport en vigueur, puis les raisons de fenêtre ci-dessus. Elle répond « ce repas peut-il juger un ratio, et lequel ? » (ratio du moment, ou ratio sport d'un type de séance). Utilisée par le mining, la comparaison avant/après et les épisodes de charge (C1) : une règle changée s'applique partout. Seules la disponibilité du verdict et la dose non nulle restent vérifiées par chaque appelant.

**Séance du ratio sport : pas une pollution (décision du 2026-10-20).** Pour juger un ratio sport, la séance qui l'a déclenché ne compte pas dans la raison `sport` : sinon aucun repas après le sport ne pourrait juger ce ratio. Une **autre** séance dans la fenêtre l'écarte toujours, comme un autre repas, une correction ou un resucrage. Sans effet sur le mining R1, qui écarte de toute façon les repas sous ratio sport.

**Où c'est appliqué.**
- `AnalyseRatioService.mapperEntrees` (mining) et `mapperEntreesDoseChangement` (comparaison avant/après changement de ratio) : même règle des deux côtés. Depuis la règle commune, la comparaison avant/après écarte aussi les repas sous ratio sport, qu'elle gardait auparavant par oubli.
- Épisodes de charge (C1, `ChargeurEpisodesCharge.evenementsRepas`) : même règle ; un repas sous ratio sport y juge le ratio sport de son type.
- Carte « Repas à revoir » (récurrences, `CalculRepasARevoir.analyser(idsPollues:)`) : un repas pollué ne compte ni comme occurrence ni comme dernier résultat. Il reste dans les faits superposés aux courbes. Les **repas isolés** (`CalculRepasIsoles`) ne sont pas filtrés : ils montrent un repas déjà hors norme (ajusté, contexte libre), pas une inférence sur un ratio.
- Faits rassemblés par `AnalyseRatioService.faitsFenetre(repas:contexte:activites:)` (injections, resucrages, séances, DIA/pic) — partagé avec l'accueil.

**Visibilité.** Comptés une fois dans `RepartitionRepasMoment.pollues` (inclus dans `ecartes` et `total`), et par raison dans `parRaisonFenetre` (un repas à deux raisons compte dans les deux). La page « Écart de ratio » énonce la règle en pied de page et donne le décompte (« 7 repas écartés pour ces raisons : autre repas dans les 4 h ×4, … »), y compris quand aucun moment n'est encore comparable. Visuel du graphique inchangé : les repas écartés n'y figurent pas.

**Prix accepté.** Moins de repas analysés, « pas assez de recul » plus longtemps.

### Traçage des changements de ratio (`DatesChangementRatio`) — implémenté
`DatesChangementRatio` (`Diaviz/modeles/profil/DatesChangementRatio.swift` ) — struct miroir de `RatiosParMoment` (`unique` , `petitDejeuner` , `dejeuner` , `gouter` , `diner` , tous `Date?` ), portée par `ProfilUtilisateur.datesChangementRatio` (optionnel avec fallback, même pattern que `photoData` ).

- **Stampée uniquement sur une vraie transition** (`SectionRatios.bindingRatioUnique`  / `bindingRatioMoment`  ) : valeur existante → valeur différente. Jamais sur `nil → valeur`  (configuration initiale) — un ratio qu'on configure pour la première fois n'invalide aucun historique.
- **Reset complet à la bascule de mode** (`bindingMode`  , unique ↔ parMoment) : les ratios sont déjà remis à zéro dans ce cas (contrainte existante), les dates le sont aussi — nouveau mode, table rase.
- `AnalyseRatioService.mapperEntrees`  filtre chaque repas par la date de changement de **sa** section (`dateChangement(section:profil:)`  , même règle de repli `.nuit → .diner`  que `InsightsService.ratioConfigure`  ) : un repas antérieur au dernier changement du ratio de son moment n'est plus éligible au mining de ce moment.
### Changement de ratio rendu visible
`AnalyseRatioService.dateChangement(section:profil:)` n'est plus privée : `CarteAnalyseRatio` la lit pour afficher « Ratio changé le , N repas depuis » tant que moins de 5 repas se sont accumulés depuis le changement. Le filtrage appliqué par cette méthode était auparavant invisible dans l'UI : un moment avec 25 repas accumulés pouvait silencieusement retomber à 2 sans explication.

### Verdict par moment — implémenté
La carte accueil et la carte de saisie rendent l'état réellement observable de chaque groupe : un verdict dès que les tranches le permettent, ou un dénominateur brut lorsque le recul reste faible. Elles ne masquent plus les repas en attente d'un seuil global.

La carte d’insight R1 « écart de ratio détecté » et la carte `CarteAnalyseRatio` ouvrent toutes deux `SheetEcartRatio`. Par principe de transparence, la sheet montre **chaque** groupe ayant au moins un repas exploitable (`filter { !$0.entrees.isEmpty }`), pas seulement ceux ayant atteint un seuil. Les sections y sont présentées dans l’ordre chronologique de la journée — petit-déjeuner, déjeuner, en-cas, dîner — plutôt que par ordre alphabétique : `CalculRatioObserve.ordreJournee(...)` suit l’ordre de déclaration, déjà chronologique, de `SectionRepas`. Le tri alphabétique précédent plaçait ainsi « Déjeuner » avant « Petit déjeuner ». Un test dédié dans `CalculRatioObserveTests` vérifie l’ordre attendu et comporte un contre-test explicite contre le retour au tri alphabétique.

(Historique, remplacé le 2026-10-09 par les gélules.) Chaque section affichait `GraphiqueZonesRatio` (un point par repas, placé selon son ratio effectif en g/u, vert/orange selon le verdict bon/moyen, rouge pour un mauvais verdict par hypoglycémie et brun pour un mauvais verdict par hyperglycémie) et une légende à 3 colonnes (« dose plus faible » / « ratio actuel » / « dose plus élevée »). La colonne gagnante reçoit un badge coloré plein couvrant titre, effectif et libellé en texte blanc : bleu « meilleur taux » lorsqu’une tranche latérale dépasse significativement le centre, ou vert « ratio confirmé » lorsqu’aucune tranche ne le dépasse.

Le bloc « Constat » est placé **en bas** de la sheet : c’est une clé de lecture, non son contenu, et le placer en tête repoussait les données réelles sous la ligne de flottaison. Sa légende emploie des pastilles rondes, pour reprendre exactement la forme des points du graphique. Chaque cause de verdict mauvais y affiche sa précision sous son libellé : seuil et fenêtre d’observation, le seuil étant lu depuis le profil de l’utilisateur.

Lorsqu’aucune comparaison n’est encore possible, le message décrit le manque dans les zones plutôt que le seul total du groupe :

- centre prêt, mais aucune zone latérale prête : « Il faut aussi 5 repas hors de votre ratio pour comparer » ;
- zone latérale prête, mais centre non prêt : « Il faut aussi 5 repas faits à votre ratio pour comparer » ;
- sinon : « N repas, M au plus dans une même zone — il en faut 5 ».Les effectifs par zone sont recalculés depuis les points eux-mêmes, car les `buckets`  ne contiennent que les zones ayant déjà franchi le seuil. Voir le document Eraser « Cartes d'insights accueil — Nouvelles tendances » pour la description complète.
- **Carte accueil** `**CarteAnalyseRatio**`  (`Diaviz/vues/accueil/CarteAnalyseRatio.swift`  ) : une ligne par moment configuré (mode `.parMoment`  : petit-déjeuner / déjeuner / goûter / dîner — pas de ligne « Nuit » séparée, mais son `effectif`  s'additionne à celui de « Dîner » puisqu'ils partagent le même ratio et la même date de changement) ou une seule ligne « Tous les repas » en mode `.unique`  . Chaque ligne affiche le libellé, le ratio actuel (« 1u/12g ») et un état : badge bleu « écart détecté » en cas d'écart significatif, badge vert « ratio confirmé » lorsqu'aucune tranche ne le dépasse, taux brut avec « peu de recul » lorsqu'aucune tranche n'a encore 5 repas, « Ratio changé le , N repas depuis » lorsqu'un changement récent compte moins de 5 repas depuis sa date, ou « Pas encore de repas analysé » sans donnée exploitable.
- **Masquage** : la carte s'efface d'elle-même uniquement si aucun ratio n'est configuré. Elle reste affichée quel que soit l'état d'analyse des groupes.
- **Carte Validation ratio (saisie)** : `ValidationRatio.effectifGroupe`  affiche simplement « N repas analysés sur ce moment, pas d'écart à signaler » chaque fois qu'aucun écart significatif n'est à remonter. Lorsqu'un écart existe, la carte affiche celui-ci. Le ratio actuel est déjà visible via le badge de profil existant (`ProfilRatio.description`  ), rien de nouveau à ce sujet.
### Contexte libre par repas
- `Repas.contexteLibre: String?`  — texte libre saisi par l'utilisateur, non structuré, **jamais interprété directement**. Saisi via une section dédiée dans `RepasSheet`  avec suggestions des contextes récents (`ContextesRepasRecentsService`  , pattern **MRU** — _Most Recently Used_ : liste triée du plus récent au plus ancien, un contexte réutilisé remonte en tête au lieu de dupliquer, taille plafonnée — même pattern que `AlimentsRecentsService`  ).
- **Exclu de tout mining** (`CalculRatioObserve`  et du regroupement composition de `CalculRepasARevoir`  ) — mais affiché sur l'accueil si le verdict est mauvais (`CalculRepasIsoles.swift`  ). Cette exclusion reste sur la seule **présence** de `contexteLibre`  , que le texte soit normalisé ou non — le paragraphe suivant est un enrichissement d'affichage uniquement.
- Dans le **journal**, le contexte apparaît en badge violet sous l'en-tête du repas (`LigneRepas.badgeContexte`  ) : il qualifie le repas lui-même, pas ses doses, donc il ne figure pas dans la ventilation d'insuline.
### Normalisation LLM du contexte libre — implémenté
Deux formulations d'un même événement réel (« voiture », « prendre la voiture ») convergent vers une entrée normalisée `{ libellé, emoji }` (ex. « 🚘 Voiture »), pour permettre un jour recherche/analyse sur ces événements. Deux moments distincts, jamais mélangés :

- `**ContexteNormalise**`  (`Diaviz/modeles/repas/ContexteNormalise.swift`  ) : struct `Codable`  /`Sendable`  — `libelle`  , `emoji`  , `variantes: [String]`  (textes bruts déjà rattachés, dédupliqués), `affichage`  (libellé + emoji combinés).
- `**ReferentielContextesService**`  (`@MainActor @Observable`  , singleton) : porte le référentiel `entrees: [ContexteNormalise]`  , persisté en **JSON dans UserDefaults** — pas dans le hub SwiftData, même classe de stockage que `AlimentsRecentsService`  (petit référentiel de catégorisation, pas un fait brut horodaté). **Non synchronisé CloudKit** : en cas de perte (réinstall, nouvel iPhone), les `contexteNormalise`  déjà résolus restent affichés (persistés côté hub), seule la convergence future de nouvelles formulations vers les entrées existantes repart de zéro.
    - `suggestions(pour texte:)`  : matching local instantané, substring bidirectionnel insensible à la casse contre `libelle`  + `variantes`  de chaque entrée (`texte.count >= 2`  ). Utilisé en temps réel dans `SectionContexteRepas`  pendant la frappe — **aucun appel LLM**.
    - `resoudre(texte:) async`  : fast path = réutilise `suggestions`  , attache la variante à l'entrée trouvée, retourne sans LLM. Sinon vérifie `SystemLanguageModel.default.availability == .available`  , appelle `ContexteNormaliseGenerator.generer`  , résout `libelleExistant`  par comparaison exacte insensible à la casse contre `entrees`  (référence hallucinée/introuvable → traitée comme nouvelle entrée, jamais un crash), sinon crée une nouvelle entrée. Persiste dans les deux cas. `nil`  si le modèle est indisponible ou la génération échoue — pas de retry automatique, l'affichage reste sur le texte brut indéfiniment.

- `**ContexteNormaliseGenerator**`  (`Diaviz/services/ContexteNormaliseGenerator.swift`  ) : appel Foundation Models, même famille que `NarrationJourVue`  mais **non-streamé** (`session.respond(to:generating:options:)`  , pas `streamResponse`  ) — job de fond sans consommateur incrémental. `@Generable struct ContexteNormaliseResultat { libelleExistant: String?, nouveauLibelle: String, emoji: String }`  . Instructions statiques interdisant explicitement toute interprétation médicale du texte (un texte comme « hypo ressentie » est traité comme une étiquette d'événement de vie, jamais comme une donnée clinique). Le prompt liste les entrées existantes (plafonné à 100) + le nouveau texte à catégoriser.
- **Câblage saisie → résolution** : `RepasService.enregistrerDepuisSaisie`  lance une `Task`  simple (pas `Task.detached`  ) juste après `enregistrer(nouveau)`  , qui appelle `resoudre(texte:)`  et écrit le résultat sur `Repas.contexteNormalise`  + sauvegarde — `nouveau`  étant déjà un `@Model`  inséré, le muter suffit, SwiftData notifie la vue automatiquement.
- **Affichage** : `CalculRepasIsoles`  utilise `r.contexteNormalise ?? contexte`  (texte brut en repli) — `CarteRepasARevoir`  n'a nécessité aucun changement, l'emoji n'étant qu'un caractère du texte affiché.
- **Pas de disclaimer IA** sur le badge normalisé (décision) : la règle du projet sur le contenu généré par IA vise l'interprétation narrative de données physiologiques ; ici le LLM catégorise un texte que l'utilisateur a lui-même écrit, proche d'un autocomplete — à revisiter si l'usage réel s'avère différent.
### Regroupement composition — « Repas à revoir » (`CalculRepasARevoir.swift`)
- Distinct du mining (qui lit `verdictPersiste`  sur tout l'historique) : ici il faut afficher une **vraie courbe CGM** par occurrence, or `ReponseGlycemique.pointsCgm`  n'est jamais persistée — donc le regroupement ne porte que sur les repas **récents** encore en mémoire (même fenêtre 45 jours qu'`AssembleurReponseRepas`  ).
- **Signature de composition**, sans LLM (garde-fou validé — romprait le principe « chaque chiffre recomptable à la main ») : aliments dont les glucides ≥ 10g (ignore garnitures négligeables), noms normalisés comparés par égalité stricte, + glucides totaux du repas à ±15g de tolérance.
- **Seuil de récurrence réglable** : `occurrencesMinimalesParDefaut = 2`  n'est que le défaut, l'utilisateur règle la valeur de 1 à 5 (`ProfilUtilisateur.preferencesAvancees.occurrencesMinimalesRepasARevoir`  , section « Repas à revoir » du profil). À 1 la récurrence est désactivée. ⚠️ Ce seuil filtre sur `occurrences.count`  , c'est-à-dire le **nombre de répétitions du plat**, sans regarder leur verdict — voir « Quoi § 4 » pour le piège de lecture que ça crée.
- **Verdict conservé par occurrence** : `OccurrencePassee { points, horsCible }`  (`RepasARevoir.swift`  ) porte le verdict de chaque occurrence passée, ce qui permet à la carte de teinter en rouge celles hors cible et d'afficher « N fois sur M hors cible ». Avant, `pointsOccurrencesPassees: [[PointCourbeRepas]]`  ne portait que les courbes : toutes se dessinaient en gris identique, rendant un plat raté 3 fois sur 3 visuellement indiscernable d'un plat raté 1 fois sur 3.
- **Aucun seuil de volume** (le garde-fou par tranche du mining ne s'applique pas ici) : contrairement au mining qui infère statistiquement sur tout l'historique, ici c'est la remontée d'un fait direct (ce repas précis, répété, a mal tourné la dernière fois) — même logique que les « Repas isolés », qui n'ont eux non plus aucun seuil.
- **Masquage** (`RepasARevoirMasquesService.swift`  , `@Observable`  singleton, `Set<UUID>`  en UserDefaults) : clé = `RepasARevoir.idRepasSource`  , l'id du **vrai** `**Repas**`  **SwiftData** ayant motivé la carte — jamais la signature du groupe, et jamais `RepasARevoir.id`  qui est régénéré à chaque recalcul. Cette clé fait réapparaître la carte automatiquement si le plat se reproduit avec un nouveau mauvais résultat, sans aucune logique dédiée : le « dernier » est alors un nouveau `Repas`  , donc un nouvel id absent du set masqué.
- **Limite acceptée** : un même repas cherché sous un nom OFF différent d'une fois sur l'autre ne sera pas regroupé — silence plutôt que faux regroupement.
### Limites connues et assumées
- Les repas enregistrés avant `doseCorrection`  restent un proxy (dose totale, correction potentiellement incluse).
- Matching de composition volontairement strict (pas de fuzzy matching, pas de LLM) — peut rater de vrais doublons.
- « Repas à revoir » n'affiche **qu'un seul constat**, celui de la dernière occurrence. Un groupe dont plusieurs occurrences sont hors cible pour des raisons différentes (une en hypo, une en hyper) ne montre que la raison de la dernière ; les autres ne sont lisibles que par la couleur de leur courbe dans le nuage. Assumé : la carte répond à « qu'est-ce qui vient de se passer », pas à « quel est le profil d'échec de ce plat ».
- Pas de mining par type de sport spécifique — attend S1/R2.
- Pas de rafraîchissement en continu en arrière-plan (voir section « Quand ») — seulement au démarrage et à chaque mutation de repas.
- Normalisation LLM du contexte libre : référentiel non synchronisé CloudKit (voir « Normalisation LLM du contexte libre » ci-dessus) ; pas de retry si la génération échoue une fois.
- Les repas ajustés sont désormais **totalement exclus** du mining — aucune donnée, même indirecte, ne renseigne si un ajustement (ex. la valeur d'une réduction sport) est lui-même bien calibré. Question ouverte pour un futur R2 (combine R1 + S1), pas résolue ici.
- Les taux sont désormais affichés sur de petits échantillons (jusqu'à 5 repas dans une tranche) : le dénominateur brut reste toujours visible et l'utilisateur juge lui-même le niveau de confiance. Aucun intervalle de confiance statistique n'est calculé.
- Les repas annotés avant l’ajout de `raisonMauvaisPersistee`  , et particulièrement ceux hors de la fenêtre de ré-annotation de 45 jours, gardent ce champ à `nil`  et retombent sur la couleur générique du verdict dans le graphique. Ils ne repasseront jamais par l’assembleur.
## Hors R1 — Glucides hebdomadaires (carte accueil)
Cette fonctionnalité est indépendante du mining du ratio (R1), mais a été livrée dans la même session de travail.

- Nouvelle carte accueil `CarteGlucidesSemaine`  (`Diaviz/vues/accueil/Glucides/CarteGlucidesSemaine.swift`  ), avec le même langage visuel que la carte score du jour : icône, titre, chevron, gros chiffre et mini-histogramme sur 7 jours. Elle affiche la moyenne quotidienne de glucides de la semaine en cours versus la semaine précédente, en grammes par jour. Elle est purement descriptive : aucune tranche n'est jugée bonne ou mauvaise, manger plus ou moins n'étant ni un succès ni un échec.
- Un tap sur la carte ouvre, par push et non par sheet, `PageGlucides.swift`  . La page affiche le même chiffre en plus grand et un histogramme Swift Charts sur 14 jours : les 7 jours de la semaine dernière en teinte atténuée, les 7 jours de cette semaine en teinte pleine.
- Calculateur pur `CalculGlucidesHebdo.swift`  (`Diaviz/services/derivation/`  ) : agrège les glucides par jour calendaire sur 14 jours et exclut les repas en mode pause (`exclureDesAnalyses`  ). Garde-fou : `joursMinimumParSemaine = 3`  . Un jour sans repas enregistré n'est pas compté comme un jour à 0 g — il peut s'agir d'un jeûne réel ou d'un trou de saisie — et est donc ignoré du dénominateur plutôt que de fausser la moyenne. Sous ce seuil sur l'une des deux semaines, `analyser(...)`  retourne `nil`  et la carte s'auto-masque.
- Service hub `GlucidesHebdoService.swift`  (`Diaviz/services/hub/`  ), sur le même pattern que `AnalyseRatioService`  : cache mémoire, recalculé aux mêmes déclencheurs (démarrage, synchronisation HealthKit, chaque repas validé).
- Couvert par `CalculGlucidesHebdoTests.swift`  .
## Dépendances
R1 → **R2** (ratio ajusté post-sport, combine R1 + S1) et **R3** (repas custom sans glucides connus) restent bloqués sur R1 mais peuvent maintenant démarrer.


## Modification d'un repas enregistré
Menu ⋯ du détail du repas → « Modifier » : même écran que la saisie, prérempli. Le repas est réécrit sur place et garde son identifiant (un masquage dans « Repas à revoir » reste valable).

- **Bolus lié** : suit la dose, l'heure et le site ; recréé s'il avait été supprimé, retiré si la dose tombe à zéro.
- **Heure changée** : l'insuline active au début est recalculée, le verdict persisté est effacé puis recalculé si le repas est dans la fenêtre d'analyse (45 jours).
- **Dose changée, même heure** : le ratio effectif persisté suit la nouvelle dose.
- **Fidélité** : le hub ne garde que des valeurs figées. La fiche d'origine sert si elle redonne les glucides enregistrés à 1 g près, sinon une fiche est reconstruite depuis ces valeurs. Le nom et l'emoji enregistrés sont conservés.
- **Trace** : « Modifié le … » sur le détail du repas (`Repas.dateModification`). Une dose corrigée après avoir vu la courbe pèse sur le ratio observé : la mention le rend visible.
- **Schéma** : `Repas.dateModification`, `Aliment.taillePortion` et `Aliment.codeProduitOFF` sont à déployer sur CloudKit Production avant la prochaine build TestFlight.

## Carte de validation à la saisie
Section « Alertes » de la saisie d'un repas : une conclusion et deux doses (saisie, au ratio), sans badge.

- Lignes facultatives : ajustement, et « Écart observé sur vos déjeuners » quand le mining a détecté un écart (jamais sous ratio sport).
- Aucune dose saisie : titre neutre « Dose au ratio : X u », icône en pointillé, pas de verdict.
- Ratio sport en vigueur : le titre dit « ratio sport », le chiffre du ratio et sa durée restante sont sur la carte sport.
- Détail au toucher, une valeur par ligne : doses, écart, ratio, ajustement, bons résultats observés, charge active. L'état du décompte des repas reste sur la page « Écart de ratio ».

## Moment d'un repas choisi à la main
Ligne « Moment » sous l'heure, à la saisie et à la modification. Par défaut automatique (heure et horaires du profil) ; un choix manuel (`Repas.momentChoisi`, à déployer sur CloudKit) ne bouge plus si l'heure change. Il pilote tout ce qui range un repas par moment : journal, ratio de référence à la saisie, mining R1, repas à revoir, épisodes C1 (`Repas.section(horaires:)`, seule lecture à utiliser). L'analyse de nuit lit l'heure réelle et n'est pas concernée.

## Ratio effectif à la saisie
Au-dessus des alertes, ratio effectif et ratio configuré côte à côte, dès qu'il y a des glucides. L'effectif = glucides / (dose de base + ajustements), hors correction. Le verdict de la carte de validation, lui, ne confronte que la dose de base : la mention « ajustement inclus » signale l'écart entre les deux lectures. Le ratio configuré est celui en vigueur aujourd'hui (moment ou sport), y compris à la modification d'un repas passé.

## Portions sur la ligne d'un aliment
Sur le repas en cours, un aliment saisi en portions affiche ses grammes puis le détail : « 100g · 2× 50g · sans insuline ». Seulement en mode portions : une quantité saisie en grammes ne se traduit pas en portions (« 2,6× 50g »).
