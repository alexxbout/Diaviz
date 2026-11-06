# Charge active — ce qui reste de sensibilité gagnée

>   Cadrage d'une métrique descriptive. **Estimation** d'un contexte, **jamais** un calcul ni une suggestion de dose. Diaviz n'est pas un dispositif médical.

**Statut** : 🟢 Livré (2026-09-23, branche `feature/charge-active`) — **seul calcul de charge de l'app**, en observation, à confronter au ressenti avant toute frise · **Implémentation** : `Diaviz/services/derivation/CalculChargeActive.swift`, `Diaviz/services/hub/ChargeActiveService.swift`, `CalculCorrelationChargeTIR.swift`

---

## 1. Pourquoi cette métrique

Constat d'usage : l'activité physique ne se comporte pas comme un événement isolé mais comme un **régime de fond** qui dure des jours ou des semaines. Quand ce régime change, la dose de lente et les ratios doivent être réajustés — et tant qu'ils ne le sont pas, les symptômes apparaissent : resucrages en série, corrections qui n'aboutissent pas, temps dans la cible qui baisse.

La boucle vécue :

```
la charge change (ex : moins de sport)
      ↓
déséquilibre → symptômes (resucrages ↑, corrections ↑, TIR ↓)
      ↓
ajustement (lente ou ratio)
      ↓
période de transition (2-3 j, données peu fiables)
      ↓
nouvel équilibre — ou nouvel ajustement
```

Aucune métrique de l'app ne représente aujourd'hui la variable de tête de cette boucle. Chaque changement de régime est donc vécu comme si c'était le premier, alors que le même chemin d'essais et d'erreurs a déjà été parcouru des mois plus tôt. La charge active est la brique manquante.

---

## 2. Ce qui existait — et ce qui l'a remplacé

> Historique : ce tableau décrit `CalculChargeContinue` tel qu'il existait au cadrage (2026-09-22). Il a été **supprimé** le 2026-09-23, voir « Un seul calcul de charge » plus bas.

`CalculChargeContinue` implémentait déjà l'essentiel de la mesure :

| Existant | Détail |
| ----- | ----- |
| Score journalier | `Σ (durée_minutes × facteur_intensité)` sur les séances du jour |
| Facteurs d'intensité | faible 1,0 · modérée 2,0 · intense 3,0 |
| Normale personnelle | moyenne hebdomadaire glissante sur 4 semaines pleines |
| Écart relatif | `(charge_semaine − normale) / normale` |
| Seuil de niveau | `seuilEcartTendance = 0,4` → haute au-delà de +40 %, basse en deçà de −40 % |
| Anti-clignotement | `joursMinimumTendance = 3` jours d'écart marqué avant d'annoncer une tendance |

`CalculCorrelationChargeTIR` s'appuie dessus pour une chronologie hebdomadaire charge / score GRI, avec marqueurs de changement de dose de lente — alimentant une page « corrélation charge/glycémie/basale » déjà livrée.

La référence explicite au *session-RPE* de Foster (durée × intensité ressentie) dans ce fichier montre que la démarche est déjà la bonne. Le présent document **ne propose donc pas une métrique nouvelle, mais cinq évolutions** de l'existant :

1. **Décroissance exponentielle** (§ 4) — aujourd'hui la charge est cloisonnée par jour puis sommée par semaine : une séance ne reporte rien sur les jours suivants, alors que son effet sur la sensibilité, lui, se reporte. C'est l'évolution principale.
2. **Marche non enregistrée** (§ 8) — absente aujourd'hui, et c'est un trou structurel.
3. **Coefficient par type d'activité** (§ 5) — seule l'intensité pèse aujourd'hui.
4. **Bande d'hystérésis** (§ 7) — un seul seuil symétrique aujourd'hui ; `joursMinimumTendance` atténue le clignotement sans l'éliminer.
5. **Définition affinée** (§ 3) — nommer ce que la métrique mesure vraiment.

Les seuils déjà en place (±40 %, 3 jours) sont proches de ceux proposés plus bas (±30 %, 4-5 jours). **Conserver l'existant et le recalibrer vaut mieux que le remplacer** : ces valeurs ont déjà été confrontées à l'usage.

### Évolution livrée (2026-09-23)

Aucun nouveau `@Model` : tout est dérivé, rien à déployer côté CloudKit.

| Évolution | Livré | Détail |
| ----- | ----- | ----- |
| Décroissance (§ 4) | ✅ | Demi-vie 24 h. Chaque apport est daté de la **fin** de la séance ou du bout de marche. |
| Normale (§ 6) | ✅ | Moyenne **temporelle du stock** sur 4 semaines se terminant 7 j avant maintenant (même exclusion de la semaine en cours que l'existant). Calculée analytiquement (intégrale exacte des exponentielles). Voir justification ci-dessous. |
| Marche (§ 8) | ✅ | Bouts ≥ 100 pas/min pendant ≥ 10 min consécutives, coefficient 0,75 × facteur faible. Préfiltrage horaire (heures ≥ 500 pas ± 1 h) avant lecture à la minute. Bout entièrement écarté s'il chevauche une séance du hub **ou** un workout Apple Santé (même ignoré à l'import). |
| Type (§ 5) | ✅ capté, non persisté | `HKWorkoutActivityType` lu à la volée par jointure `workoutUUID`, coefficient 1,0 partout. Pas de nouveau champ dans `HealthKitWorkoutData` : ça aurait imposé un déploiement de schéma pour une valeur sans effet sur le calcul, et l'UUID déjà persisté permet de la relire à tout moment. |
| Intensité (§ 5) | ✅ FC | FC moyenne du workout (relue à la volée, repli sur celle figée à l'import), interpolée en continu : 50 % FCmax → 1, 70 % → 2, 90 % → 3, bornée [1, 3]. FCmax **personnelle** depuis le 2026-09-26 (§ 5, « FC max personnelle »), 190 en repli — même valeur pour `intensiteDepuisFC`. Sinon `IntensiteSport`. |
| `workoutEffortScore` | ❌ non utilisé | L'API existe (iOS 18+, `HKWorkoutEffortRelationshipQuery`), mais la valeur n'existe que si l'effort a été noté sur la montre après la séance, et exige une autorisation et une requête de relation en plus. La FC couvre déjà le besoin. |
| Hystérésis (§ 7) | ✅ | Voir § 7 — valeurs retenues. |
| Affichage | ✅ minimal | Carte « Charge active » en tête de `PageCorrelationChargeGlycemie` : niveau, écart en % à la normale, « depuis N j », sources (partiel si pas non lus). Jamais le nombre brut. |

Autorisations Santé ajoutées au préflight de démarrage : `stepCount` et `heartRate` (usage string mise à jour).

**Pourquoi la normale doit être en charge active.** En régime établi, un stock alimenté de `c` points par jour oscille autour d'une moyenne `c × τ`, avec `τ = demi_vie / ln 2 ≈ 1,44 j`. Rapporter le stock à l'ancienne normale (somme hebdomadaire / 7 = `c`) donnerait un indice moyen de 1,44 pour une semaine parfaitement habituelle. Numérateur et dénominateur doivent donc être le même objet — le stock — l'un à l'instant, l'autre moyenné dans le temps. Vérifié par test (`normaleMemeUnite`).

**Une seule lecture de l'indice (révisé le 2026-09-26).** La première version affichait l'indice **instantané** (§ 6) à côté d'un niveau calculé sur la moyenne journalière. À l'usage, « Charge active normale » à côté de « +53 % » se contredisait : l'indice instantané bondit juste après chaque séance (à trois séances par semaine, ~2 le soir d'une séance, ~0,5 au creux du dimanche). L'indice affiché est désormais celui qui fixe le niveau : **moyenne du stock sur la journée** (jusqu'à maintenant pour aujourd'hui) / normale de ce jour. La formule instantanée reste le moteur du stock, elle n'est plus montrée.

**Début d'historique (corrigé le 2026-09-26).** L'historique exploitable commence à la date **la plus tardive** des sources présentes (premier pas, première séance du hub), pas la plus ancienne. Avec la plus ancienne, les pas (présents depuis des années) ouvraient la normale sur une période où aucune séance n'était encore saisie : normale quasi nulle, indice aberrant (premières semaines largement au-dessus de toutes les autres). Conséquence : l'argument « la normale est significative dès l'autorisation grâce aux pas » (§ 8) ne tient que pour la part marche ; tant que les séances d'avant août 2026 manquent au hub, le recul part de la première séance saisie.

**Chronologie simplifiée (2026-09-26).** Le graphique ne montre que la charge de chaque semaine rapportée à la référence, face au score GRI. Les repères de changement de dose de lente sont retirés : ce graphique sert à valider la charge elle-même, la mise en relation avec les paramètres (lente, ratios) viendra avec la frise C1. Une semaine sans comparaison possible (moins de 5 semaines d'historique avant elle) n'a pas de barre ; un mode d'emploi court sous le graphique le dit. Une colonne grise pleine hauteur a été essayée puis retirée : elle chargeait le graphique sans rien apprendre.

**Un graphique, une seule échelle graduée (2026-09-26).** Charge et score GRI partageaient deux échelles graduées : la barre se lisait sur l'échelle du score (« elle approche 100 ») et la ligne de référence, orange derrière des barres orange, disparaissait. Essai de deux graphiques séparés, écarté (préférence pour un seul). Retenu : un seul graphique dont la seule échelle graduée est celle du score (à droite, 0 à 100, en bleu) ; la charge se lit contre la ligne de référence (pointillé neutre dessiné devant les barres, nommé dans la légende) ; le % d'écart s'affiche au tap sur une semaine, pas au-dessus des barres. Chaque barre a sa propre référence (ses 4 semaines précédentes) : une valeur unique en légende était fausse pour toutes les autres semaines (essayé puis retiré). La référence **de la semaine sous le doigt** s'affiche en faits dans une bulle en haut du graphique (même patron que le graphique d'une nuit B1), avec la charge et le score GRI ; le mode d'emploi est replié par défaut. Exemple de référence : « 2,5 séances (2 h 10) + 40 min de marche par semaine », jamais en points. Ligne de référence en gris.

**Vocabulaire (2026-09-26).** À l'écran, « normale » est remplacé par **« référence »** (la moyenne personnelle des 4 semaines de référence) : « +30 % par rapport à votre référence », niveaux « basse / dans la référence / haute ». Le code garde `normale` (fonction, cas `NiveauChargeActive.normale`) : seul le libellé change.

**Dédoublonnage confirmé.** Les pas faits pendant une séance ne comptent jamais comme marche : un bout qui chevauche une séance du hub (saisie ou importée) ou un workout Apple Santé (même jamais importé) est écarté en entier. Limite : une séance saisie à la main avec une mauvaise heure ne chevauche rien, ses pas peuvent alors compter comme marche.

**Temps de chargement (mesuré sur l'iPhone, 2026-09-26).** Première version : ~9 s par passage (tri de tous les pas pour trouver le premier : 2,7 s ; 220 requêtes minute sur un préfiltre par heures trop lâche : 6,2 s), et le passage attendait toute la séquence de démarrage (B1, B2/B3, synchro CGM). Corrections :

- passage lancé dès l'ouverture si l'autorisation Santé est déjà tranchée, en parallèle du reste du démarrage ; un second appel attend le passage en cours au lieu d'en relancer un ;
- premier pas : un échantillon quelconque antérieur à la fenêtre suffit (requête sans tri, ~10 ms) ;
- préfiltre par blocs de 10 min (paire de blocs voisins ≥ 1 000 pas, condition nécessaire, testée), plages proches (< 3 h) fusionnées, 4 requêtes minute à la fois au plus ;
- **cache des bouts des jours clos** (`UserDefaults`, clé versionnée `chargeActive.cacheBoutsMarche.v1`) : faits dérivés d'Apple Santé, propres à l'appareil, recalculés s'ils sont perdus. Seuls les 2 derniers jours sont relus à la minute (la montre synchronise parfois en retard).

Résultat : ~2,3 s au premier lancement sans cache, **~0,4 s** ensuite. Onglet Analyses : relecture Santé seulement si le dernier passage date de plus de 15 min. Carte d'accueil en placeholder pendant le calcul.

**Bouts de marche : 0 puis 68.** La première version trouvait 0 bout sur 160 jours ; le préfiltre par blocs en trouve 68 (dont 3 sur les 14 derniers jours : 15, 16 et 23 septembre en soirée, 10 à 20 min à ~105-110 pas/min). Le nouveau préfiltre est prouvé sans faux négatif ; l'ancien aurait dû les trouver aussi. Hypothèse non prouvée : les ~220 requêtes minute lancées simultanément revenaient vides sans erreur. **Vérifié par l'utilisateur le 2026-09-26** : les bouts récents correspondent à de vraies marches. Seuil de 100 pas/min conservé.

### Un seul calcul de charge (2026-09-23)

Trois calculs de charge coexistaient, avec le même vocabulaire et des résultats différents : la charge continue (`CalculChargeContinue`, séances seules, somme hebdo), les paliers de séances sur 7 jours (`CalculChargeActivite` / `ChargeActivite` : tranquille / moyenne / intense, utilisés par B2/B3) et la charge active. Une même semaine pouvait être « basse » à l'accueil et « normale » dans Analyses. Les deux premiers sont **supprimés**.

**Contexte partagé.** `ChargeActiveService.shared` calcule une fois un `ContexteChargeActive` sur 90 jours (`horizonJours`) : apports, faits par jour (séances, minutes, marche) et niveau par jour. L'hystérésis est rejouée **une seule fois** sur toute la série : deux écrans qui parlent du même jour lisent forcément le même niveau. Recalcul complet au démarrage (après l'autorisation Santé) et à chaque ouverture de l'onglet Analyses ; recalcul léger (faits Santé en cache) à chaque changement de séance.

| Écran | Avant | Maintenant |
| ----- | ----- | ----- |
| Accueil — carte et page « Activité » | niveau + écart + tendance (séances seules) | **faits bruts seulement** : séances (nombre, minutes) et marche soutenue (minutes), 7 j / 14 j. Aucun niveau : l'accueil affiche, Analyses interprète |
| Analyses — carte « Charge et glycémie » | niveau hebdo propre à la page | niveau de charge active |
| Page « Charge et glycémie » — chronologie | somme hebdo brute (points) | indice moyen de la semaine (stock moyen / normale), ligne « normale » à 1 |
| Page — TIR et dérive par tranche | semaines classées vs moyenne des 10 semaines | **jours** classés par niveau de charge active du jour (`n` en jours) — **supprimé le 2026-10-18** (remplacé par les épisodes C1) |
| Badge du repas (`ValidationRatioCard`) | niveau + tendance ancienne charge | niveau de charge active au moment du repas, « · N j » depuis la bascule |
| Verdict de nuit B1 | tendance ancienne charge | « Charge active haute/basse depuis N j », seulement hors normale |
| Détail de soirée | ligne ancienne charge + pastille B2/B3 | pastille seule (niveau du jour) — la ligne faisait doublon |
| B2/B3, recherche « Comparer à ce soir » | paliers de séances 7 j | niveau de charge active du jour ; pastille et critère seulement hors normale |

**Conséquence sur B2/B3** : le critère de recherche « même charge » compare désormais des niveaux basse / normale / haute (hystérésis comprise), plus des nombres de séances. Tant que la normale n'est pas établie, un soir n'a pas de niveau : ni pastille, ni critère.

---

## 3. Définition

**Impact résiduel des séances passées sur la sensibilité à l'insuline.**

Ce que cette définition exclut, volontairement :

- ce **n'est pas** un volume d'activité ni un score de forme ;
- ce **n'est pas** la réponse glycémique pendant ou juste après une séance — cette question est traitée ailleurs (S1, verdicts de resucrage, courbe autour de la séance).

La distinction est structurante. Sur la réponse aiguë, endurance et renforcement divergent : l'endurance fait plutôt baisser la glycémie, le travail en force peut la faire monter (décharge d'adrénaline). Sur la **sensibilité résiduelle** en revanche, les deux poussent dans le même sens : déplétion du glycogène et captation musculaire accrue du glucose. Un scalaire unique est donc cohérent pour cette dimension-là, et seulement pour elle.

Parallèle avec l'IOB, qui n'est pas qu'une analogie de forme :

| | Ce que ça représente |
| ----- | ----- |
| **Insuline active** (IOB) | ce qui reste d'insuline en action |
| **Charge active** | ce qui reste de sensibilité gagnée |

Deux stocks résiduels qui agissent sur la glycémie à l'instant présent à cause d'événements passés. Même math, même logique de lecture.

---

## 4. Formule

Un stock qui monte à chaque activité et décroît en continu. Plus simple que l'IOB : pas de pic différé, l'effet démarre immédiatement.

Pour `N` séances de charge `charge_i` réalisées aux instants `t_i` :

```
charge_active(T) = Σ_i  charge_i · exp(−λ · (T − t_i))

λ = ln(2) / demi_vie
charge_i = coefficient_type · coefficient_intensité · durée_minutes
```

C'est une **dérivation** : calculée à la volée depuis les activités du hub et HealthKit, jamais persistée (« un hub, des dérivations »).

### Demi-vie : 24 h

La demi-vie est le temps au bout duquel il reste **la moitié de ce qui restait** — décroissance proportionnelle, jamais tout à fait nulle.

Ce que laisse une séance de 120 points :

```
maintenant  120
+24 h        60
+48 h        30
+72 h        15
+96 h         7,5
```

**Demi-vie ≠ durée de l'effet.** La durée utile correspond plutôt à 3-4 demi-vies (le moment où il ne reste que ~10 %). Le vécu rapporté — effet prolongé sur au moins 48 h après une séance isolée de course à pied — est cohérent avec une demi-vie de 24 h : il reste alors 25 % à 48 h, ce qui compte encore tout en s'éteignant. Une demi-vie de 48 h ferait au contraire compter une séance du dimanche pour un tiers le mercredi suivant, ce qui contredit le vécu.

Valeur **à recalibrer** une fois qu'un historique réel existe.

### L'accumulation est le sujet

L'intérêt de la formule n'est pas de décrire une séance mais leur empilement. Trois séances par semaine, demi-vie 24 h :

```
lun  séance ──▶ 120
mar             60
mer  séance ──▶ 30 + 120 = 150
jeu             75
ven  séance ──▶ 37 + 120 = 157
sam             78
dim             39
```

Le stock monte semaine après semaine tant que les séances s'enchaînent. **C'est cela, un régime de charge haute** — une accumulation, pas une séance.

---

## 5. Pondération : deux axes indépendants

### Type d'activité

`HKWorkoutActivityType` est déjà présent sur chaque workout importé — la dimension est donc gratuite.

**Décision** : enregistrer le type dès le départ, mais appliquer un **coefficient de 1 partout** tant qu'aucune preuve ne justifie de différencier les familles (endurance / force / mixte / marche). Calibrer trois coefficients de famille est hors de portée avec le volume de données disponible ; la dimension est captée, la calibration attend.

### Intensité

Ordre de priorité :

1. **FC moyenne** de la séance, si des échantillons cardio existent — de loin le plus fin ;
2. **score d'effort** type Apple Watch, s'il est réellement exposé — `workoutEffortScore` existe sur iOS récent, **à vérifier** avant de compter dessus ;
3. **enum manuel** en repli (`IntensiteSport`), à élargir de 3 à ~5 crans.

### FC max personnelle (2026-09-26)

**Implémentation** : `Diaviz/services/derivation/CalculFCMax.swift` (pur), lecture dans `HealthKitChargeActiveLecteur.picsSoutenus`, orchestration et cache dans `ChargeActiveService.calculerFCMax`.

Le rapport FC moyenne / FC max fixe le poids de chaque séance. Avec 190 pour tout le monde, ce poids dépendait d'une constante sans rapport avec l'utilisateur. La FC max est désormais **observée** sur ses propres séances.

**Définition.** Pour chaque workout Apple Santé des 12 derniers mois (importé dans le hub ou non) : **pic soutenu** = maximum, sur la séance, de la **médiane** des échantillons FC d'une fenêtre glissante de 60 s (fenêtres d'au moins 3 échantillons, sinon ignorées). FC max observée = plus haut pic soutenu parmi les séances.

**Pourquoi ce choix plutôt qu'un percentile.**

- Maximum brut : un seul artefact capteur (230 bpm) fausserait tout. Écarté.
- Percentile élevé de tous les échantillons : il mesure surtout la durée des séances faciles. La FC max n'est tenue que quelques dizaines de secondes en fin d'effort maximal ; sur une année de séances modérées, le 99ᵉ percentile tombe loin en dessous. Écarté.
- Pic soutenu : un vrai sommet tient plusieurs échantillons d'affilée (la montre échantillonne toutes les ~5 s en entraînement), un artefact non. Pour passer la médiane, une valeur doit occuper au moins la moitié de sa fenêtre : un ou deux échantillons aberrants dans une fenêtre de ~12 sont sans effet. Retenu.

**Garde-fous.**

| Garde-fou | Valeur | Raison |
| ----- | ----- | ----- |
| Échantillon écarté | hors 30-250 bpm | Erreur de mesure évidente |
| Fenêtre ignorée | < 3 échantillons | Échantillonnage épars (hors mode entraînement) : rien ne prouve que la valeur a été tenue |
| Séance écartée | pic soutenu > 220 bpm | Invraisemblable chez un adulte : artefact prolongé |
| Minimum | 10 séances avec pic mesurable | En dessous, repli sur 190, affiché « théorique » |
| Historique | 12 mois | La FC max baisse avec l'âge (~1 bpm/an) |

**Limite assumée.** Une FC max observée est une **borne basse** : si aucune séance n'approche l'effort maximal, elle sous-estime la vraie FC max et **surestime** les intensités. Le nombre de séances est affiché avec la valeur pour qu'on sache sur quoi elle repose. L'effet reste amorti par la nature relative de l'indice (stock / référence personnelle, pondérée par la même FC max).

**Une seule source.** `ChargeActiveService.fcMax` (`FCMaxRetenue` : bpm, origine observée / théorique, nombre de séances) alimente `CalculChargeActive.facteurIntensite` et `intensiteDepuisFC` (pré-remplissage de l'intensité à l'import). `CalculChargeActive.fcMaxTheorique` et le `190` codé en dur de `intensiteDepuisFC` sont supprimés ; le repli vit dans `CalculFCMax.fcMaxTheorique`.

**Aucun stockage synchronisé.** Dérivée et recalculée à chaque passage complet, aucun nouveau `@Model`, rien à déployer côté CloudKit. Seul un cache **propre à l'appareil** des pics par séance (`UserDefaults`, clé versionnée `chargeActive.picsFCSeances.v1`) évite de relire les échantillons FC d'une année de séances à chaque lancement ; les séances terminées depuis moins de 24 h sont toujours relues (synchronisation tardive de la montre). Perdu, il est recalculé.

**Affichage.** Une ligne sous la carte « Charge active » (page « Charge et glycémie »), là où la carte explique déjà le calcul : valeur, origine (observée / théorique) et nombre de séances. Rien ailleurs.

**Conséquence.** Changer la FC max réécrit le poids de **toutes** les séances passées, donc les indices et niveaux de charge historiques (voir journal du registre).

**Pourquoi la FC ne suffit pas seule**, et pourquoi le type reste nécessaire :

- une série lourde dure ~40 s puis repos ; la FC pique et retombe, la moyenne sur une heure de séance peut valoir celle d'une marche tranquille — alors que la déplétion de glycogène est massive ;
- la FC traduit une **demande cardiaque**, pas une captation musculaire de glucose : les deux vont ensemble en endurance, elles se découplent en force ;
- la FC monte aussi pour des raisons non métaboliques (chaleur, stress, caféine, déshydratation) ;
- sur de l'anaérobie intense, l'adrénaline monte la FC **et** la glycémie : la FC corrèle alors avec l'effet aigu opposé.

---

## 6. Le nombre brut ne doit jamais être affiché

`intensité × durée` produit des unités arbitraires : une séance modérée d'une heure vaut 120 « points », ce qui ne signifie rien dans l'absolu. Seule compte la position **relative à l'historique de l'utilisateur** :

```
indice = charge_active(T) / charge_active_moyenne(N dernières semaines)
```

- `≈ 1` → conforme à l'habitude
- `> 1` → au-dessus de l'habituel
- `< 1` → en dessous

L'indice est auto-référencé : aucune norme externe, aucune comparaison à une population.

La forme est inspirée du rapport charge aiguë / charge chronique du sport de haut niveau. **Inspirée seulement** : cette métrique est méthodologiquement contestée dans la littérature. On en reprend la forme, pas la prétention de validité.

---

## 7. Régime : seuils et hystérésis

La délimitation des périodes (§ 9) a besoin d'un régime discret.

| Régime | Indice |
| ----- | ----- |
| Bas | < 0,70 |
| Normal | 0,70 – 1,30 |
| Haut | > 1,30 |

**Bande d'hystérésis** : on entre en régime haut à 1,30, on n'en sort qu'en repassant sous **1,15**. Deux seuils différents selon qu'on entre ou qu'on sort.

**Collant** : exiger 4 à 5 jours consécutifs au-delà du seuil avant de déclarer un changement de régime. Plus court qu'une semaine (un vrai basculement est capté vite), plus long qu'un week-end (une grosse sortie du samedi ne fait pas basculer le régime).

```
      j1 j2 j3 j4 j5 j6 j7 j8 j9 10 11 12
1,5  ┤                  ●
1,4  ┤      ●  ●     ●     ●
1,3  ┤╌╌╌╌╌╌╌╌╌╌╌╌●╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌  ENTRÉE
1,2  ┤   ●                 ●  ●
1,15 ┤╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌  SORTIE
1,1  ┤                           ●
1,0  ┤●                             ●
     └──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──

régime : normal ──────▶│◀── haut ──────▶│ sortie
                       ↑                ↑
                  j3→j6 : 4 jours    j11 : passe
                  au-dessus de       sous 1,15
                  1,30 → bascule
```

**Le moment qui compte : j9 et j10.** L'indice redescend à 1,2 — sous le seuil d'entrée mais au-dessus du seuil de sortie : on **reste** en régime haut. Sans la bande, avec un seuil unique à 1,30, ces deux jours produiraient une sortie puis une rentrée, soit quatre « périodes » d'un jour, toutes inexploitables.

**Valeurs retenues à l'implémentation (2026-09-23)** — l'existant a été conservé plutôt que les valeurs ci-dessus :

| | Proposé | Retenu |
| ----- | ----- | ----- |
| Entrée haut / bas | 1,30 / 0,70 | **1,40 / 0,60** (`seuilEntreeNiveau` = 0,4, repris de l'ancien `seuilEcartTendance`) |
| Sortie haut / bas | 1,15 / 0,85 | **1,25 / 0,75** (`seuilSortieNiveau` = 0,25) |
| Jours consécutifs | 4-5 | **3** (`joursMinimumBascule`, repris de l'ancien `joursMinimumTendance`) |

Le minimum de jours s'applique à **tout** changement de niveau, entrée comme sortie. Un jour sans indice calculable remet le compteur à zéro. La date de bascule retenue est le premier jour de la série d'écart.

**Durée minimale** : une période plus courte que la phase de transition (2-3 j) n'a aucune phase stable exploitable → la marquer **non exploitable** plutôt que d'y calculer des moyennes sans valeur.

---

## 8. Sources de données

### Séances enregistrées

`ActiviteSportive` (saisie dans l'app) et workouts importés depuis HealthKit (`HealthKitImportService`).

### Marche non enregistrée comme séance

`HKQuantityTypeIdentifier.stepCount` et `.distanceWalkingRunning` sont alimentés en continu par le coprocesseur de mouvement, indépendamment de toute séance démarrée. Une marche quotidienne soutenue représente une charge métabolique réelle ; l'ignorer fausse la métrique à sa racine.

**Ne pas compter tous les pas.** Une journée à 4 000 pas relève du métabolisme de base, pas de la charge. Deux approches :

- compter l'**excédent** au-dessus de la ligne de base personnelle ;
- ne retenir que les **bouts de marche soutenue** (cadence ≥ ~100 pas/min pendant ≥ 10 min).

La seconde est plus proche du vécu « j'ai marché aujourd'hui ».

**Dédoublonnage** : une marche déjà enregistrée comme `HKWorkout` ne doit pas être recomptée depuis les pas. Exclure les bouts détectés qui chevauchent la fenêtre d'une séance enregistrée.

### L'historique des pas existe déjà

Point important : contrairement au hub, dont la saisie réelle démarre en août 2026, **l'historique de pas présent sur l'iPhone remonte potentiellement à des années**. Dès l'autorisation accordée, la moyenne personnelle de référence (dénominateur de l'indice, § 6) devient immédiatement significative.

C'est la seule métrique de l'app qui échappe au problème du « pas assez de recul ».

**Réserve** : le versant glycémique (resucrages, TIR) ne remonte pas avant août 2026. Charge active profonde, **mise en relation avec les résultats récente**.

---

## 9. Ce que la métrique débloque

Modèle à deux niveaux, qui structure l'historique au lieu de l'effacer :

```
RÉGIME « charge haute »        (plusieurs semaines de sport soutenu)
   ├── période : lente 20 U  →  2,8 resucrages/j, TIR 61 %
   ├── période : lente 18 U  →  1,5 resucrage/j,  TIR 68 %
   └── période : lente 17 U  →  1,2 resucrage/j,  TIR 72 %

RÉGIME « charge basse »        (semaines sans sport)
   ├── période : lente 17 U  →  corrections inefficaces, TIR 58 %
   └── période : lente 19 U  →  TIR 70 %
```

### Définition d'une période

Un intervalle pendant lequel aucun paramètre n'a été modifié. Le vecteur de paramètres :

```
(lente, ratio matin, ratio midi, ratio soir, ratio(s) sport, facteur de correction)
```

Le **facteur de correction** ≈ 0,40 g/L par unité (1 U fait baisser d'environ 0,40 g/L). Il varie rarement, mais il varie.

Une moyenne calculée à cheval sur un changement de paramètre ne décrit aucune réalité — ni celle d'avant, ni celle d'après.

### Invalidation par dimension, pas globale

Plus le vecteur s'élargit, plus les périodes se fragmentent : n'importe lequel des six paramètres qui bouge ouvrirait une nouvelle période, et l'on se retrouverait avec beaucoup de périodes trop courtes pour être exploitables.

La parade : **chaque analyse déclare de quelles composantes du vecteur elle dépend**.

| Analyse | Dépend de |
| ----- | ----- |
| B1 (basale) | lente |
| R1 — midi | ratio midi, facteur de correction |
| R1 — soir | ratio soir, facteur de correction |
| Analyses sport | ratio(s) sport |

Changer le ratio sport n'invalide pas le petit-déjeuner. Le vecteur reste global pour **décrire** une période ; l'invalidation, elle, est par dimension. C'est déjà le comportement en place côté ratios : le principe est généralisé, pas inventé.

### Le manque n'est pas le reset, c'est l'archivage

Repartir de zéro à chaque changement de paramètre est **correct sur le principe de segmentation**. Ce qui manque, c'est la conservation : la période close disparaît au lieu de rester comparable. Le jour où la charge remonte, la phrase « la dernière fois que j'étais en charge haute, ça s'était stabilisé à 17 U » devrait être lisible dans l'app.

Ce volet (frise de périodes, comparaison entre régimes) n'est pas cadré ici. Il dépend entièrement de cette brique.

---

## 10. Ce que ça apporte concrètement

- **Voir le basculement arriver.** Aujourd'hui le changement de régime se découvre *par les symptômes* — une semaine de resucrages avant de comprendre. L'indice bascule avant.
- **Retrouver ce qui avait marché** dans le même régime, au lieu de refaire le même chemin d'essais et d'erreurs.
- **Savoir quand la transition est finie**, donc éviter de réajuster sur le bruit du changement précédent — ce qui relance la boucle.
- **Répondre à la question « les ratios changent-ils trop souvent ? »**, aujourd'hui sans réponse possible puisque la preuve est détruite à chaque fois.

---

## 11. Ressenti de charge — collecte pour calibration

Estimer soi-même son niveau de charge n'est pas évident. Une saisie rapide du **ressenti de charge** permettrait de collecter une référence subjective et de recalibrer plus tard les paramètres du § 4.

**Limite méthodologique à ne pas oublier** : ce ressenti est en grande partie dicté par les ajustements que les séances ont imposés — donc par les conséquences glycémiques observées. L'utiliser pour valider une métrique censée justement anticiper ces conséquences est **partiellement circulaire**.

Ce n'est pas rédhibitoire, mais il faut l'appeler par son nom : ce que mesure ce ressenti est un **impact métabolique perçu**, pas un volume d'activité. C'est sans doute plus utile pour l'usage visé — à condition de ne pas le présenter comme une validation indépendante du calcul.

---

## 12. Dégradation gracieuse

- **Autorisation HealthKit sur les pas non accordée** → charge calculée sur les séances seules, **signalée comme partielle**.
- **Aucune séance ni marche détectée** → charge nulle, et la notion de régime n'a pas de sens : le dire explicitement plutôt que d'annoncer « régime bas » comme s'il s'agissait d'un constat.
- **Historique plus court que la fenêtre de référence** → pas de moyenne personnelle, donc pas d'indice → « pas assez de recul ».

---

## 13. Ce que ce n'est pas

- Pas un score de forme ni de performance — aucune incitation à s'entraîner davantage.
- Pas une prédiction.
- Ne débouche sur **aucune** suggestion de dose, jamais. Strictement descriptif.

---

## 14. Emplacement

Pas de nouvelle page (décision 2026-09-23) : la métrique fait évoluer la page existante « Charge et glycémie » (`PageCorrelationChargeGlycemie`), avec la frise des périodes — voir [C1 — Frise des périodes](../analyses/C1%20—%20Frise%20des%20périodes.md).

L'accueil (carte et page « Activité ») n'affiche que les faits bruts de la même source — jamais un niveau.

---

## 15. Questions ouvertes

- Recalibrage de la demi-vie sur données réelles (24 h retenu comme point de départ).
- ~~`workoutEffortScore` réellement exposé sur iOS ?~~ Oui (iOS 18+), mais dépend d'une notation manuelle sur la montre — non utilisé (§ 2).
- Différenciation des coefficients par famille d'activité — quand le volume le permettra.
- ~~Excédent de pas ou bouts de marche soutenue ?~~ Bouts de marche soutenue (2026-09-23).
- ~~Durée exacte de l'hystérésis (4 ou 5 jours).~~ 3 jours, valeur existante conservée — à revoir après observation.
- Cadence stricte minute par minute : un feu rouge coupe un bout. Tolérer une minute sous le seuil ? Au 2026-09-26 : aucune marche à ce rythme sur les jours observés, 0 min est cohérent — à revoir si une vraie marche soutenue n'apparaît pas.
- ~~L'indice instantané oscille fortement entre deux séances : l'afficher ?~~ Non — indice de la journée affiché (2026-09-26, § 2).

---

## 16. Modes de défaillance

Par profondeur croissante. Les trois premiers sont corrigeables, le quatrième est une hypothèse de modélisation.

1. **Entrées manquantes** — séances non enregistrées, autorisation sur les pas non accordée → charge sous-estimée.
2. **Mauvaise constante de décroissance** → charge attribuée aux mauvais jours.
3. **Mauvaise pondération** → 30 min intenses et 2 h de marche tranquille pèsent pareil alors que l'impact diffère.
4. **Forme du modèle** — réserves connues : le coefficient devrait probablement différer selon la famille d'activité (question de calibration, pas de forme) ; un effort très traumatisant musculairement peut créer une résistance locale transitoire, inversant brièvement l'effet ; deux séances très rapprochées ne s'additionnent probablement pas de façon parfaitement linéaire (saturation, effet de second ordre non modélisé).

**Avertissement** : c'est la brique sous tout le reste — frise de périodes, comparaison entre régimes, lecture des symptômes. Si la charge active est fausse, tout ce qui s'empile dessus est faux. Elle doit être validée contre le vécu — « cette semaine-là je me sentais en charge haute, que dit l'indice ? » — **avant** de construire quoi que ce soit par-dessus.

---

## Annexe — Pistes écartées

**Apprentissage automatique** (détection des paramètres qui co-varient). Écarté, et pas pour une raison de volume : la charge, la lente et les ratios bougent **toujours ensemble**, puisqu'ils sont ajustés en réaction au même déclencheur. Aucun modèle ne peut séparer leurs effets respectifs dans ces conditions — c'est un problème d'**identifiabilité**, que davantage de données ne résout jamais. S'y ajoute que l'unité d'observation est la période, pas le jour : quelques dizaines d'observations au total, pas des milliers.

Méthodes examinées et écartées avec elle : inférence causale (exigerait un instrument ou une randomisation inexistants), modèles bayésiens hiérarchiques (honnêtes sur petit échantillon, mais répondent « incertain » — ce que la lecture descriptive dit déjà, en plus lisible), protocole N-of-1 (seule approche rigoureuse pour un patient unique, mais alterner délibérément ses doses relève d'une décision médicale, hors du rôle de l'app).

Le besoin réel n'est pas une prédiction mais une **mémoire** : « la dernière fois que j'étais dans cette situation, qu'est-ce qui avait marché ? ». C'est une consultation d'historique, pas un modèle.
