# C1 — Frise des périodes

>   Retrouver ce qui était en place, et ce qui remplissait les critères de l'utilisateur, les fois précédentes où sa charge d'activité était comparable. **Descriptif strict** : aucune suggestion de dose, aucun classement « meilleur réglage ». Diaviz n'est pas un dispositif médical.

**Statut** : 🟢 V1 livrée le 2026-10-18 (branche `feature/c1-episodes`), maquette validée le même jour, recadré le 2026-09-27 — enregistreur livré le 2026-09-23 (§ 2) · **Dépend de** : [Charge active (sport)](../architecture/Diaviz%20—%20Charge%20active%20(sport).md), [B1](B1%20—%20Détection%20basale.md), [R1](R1%20—%20Réponse%20glycémique%20post-repas.md)

> Le nom du fichier est conservé pour ne pas casser les liens. La « période » définie par un vecteur de réglages constant a été **abandonnée** (voir § 3) : le découpage se fait désormais par **épisode de charge**.

---

## 1. Le besoin

> À l'entrée dans un niveau de charge, la page montre quels réglages remplissaient les critères les fois précédentes à charge comparable, et comment ça se passait. Après un changement de réglage, elle montre ce que ce changement a donné.

Deux usages, une seule page (« Charge et glycémie », `PageCorrelationChargeGlycemie`) :

1. **Mémoire par situation.** Exemple : charge active élevée, glycémie qui remonte en pleine nuit depuis plusieurs jours, ratios du matin et du midi un peu trop forts. La question : « existe-t-il un moment où la même dose de lente était déjà en place, comment ça se passait, et avec ce niveau de charge, quels ratios étaient en place ? »
2. **Avant / après un changement.** Ce qu'un changement de réglage a donné, jugé sur les critères propres à ce réglage.

Contraintes posées :

- **Réduire la charge mentale.** Le moins d'information possible à l'écran. La page ne doit pas se réorganiser à chaque changement de réglage.
- **Le graphique existant reste tel quel** : charge par semaine face au score GRI. Aucun réglage dessus.
- **Rester humble.** Fatigue, émotions, maladie : une partie de la réponse glycémique n'est pas mesurée. Des loupés existent toujours, les critères doivent les tolérer.
- **Les ratios en font partie**, y compris les ratios sport : c'est ce qu'on ajuste quand la charge monte, et la charge des jours passés influe aussi sur les ratios hors sport.

---

## 2. Prérequis — l'historique des paramètres

> ✅ **Enregistreur livré le 2026-09-23** (branche `feature/historique-parametres`). L'historique des ratios et du facteur de correction s'accumule à partir de cette date ; rien n'existe avant. Détail en fin de section, « Enregistreur livré ».

Vérifié dans le code le 2026-09-22 :

| Paramètre | Stockage actuel | Reconstituable rétroactivement ? |
| ----- | ----- | ----- |
| Dose de lente | événements `Injection` du hub | ✅ **Oui** — chaque injection porte sa dose et sa date |
| Ratios par moment | `ProfilUtilisateur.ratiosParMoment` — valeur courante | ❌ Non |
| Date du dernier changement de ratio | `ProfilUtilisateur.datesChangementRatio` | ⚠️ Date seule, **sans la valeur** |
| Facteur de correction | `ProfilUtilisateur.ratioCorrection` — valeur courante | ❌ Non, ni valeur ni date |
| Ratios sport | `ProfilUtilisateur.ratiosSport` — valeur courante | ❌ Non, ni valeur ni date |

Autrement dit : **les valeurs passées des ratios sont définitivement perdues**. Accepté : l'historique repartira du jour de livraison de l'enregistreur. `DatesChangementRatio` permet de borner la période *courante* (c'est son rôle pour le mining R1), pas de reconstituer les précédentes.

### Conséquence de conception

La frise ne peut pas être rétroactive sur les ratios. **L'enregistreur doit être construit avant l'afficheur**, et l'historique ne commencera à s'accumuler qu'à partir du jour où il est livré.

Cela plaide pour livrer la persistance **en premier et séparément**, même sans interface : chaque jour d'attente est un jour d'historique définitivement perdu. La frise, elle, peut venir des mois plus tard.

### Ce que l'enregistreur doit capter

À chaque modification d'un paramètre : la date, le paramètre concerné, l'ancienne valeur, la nouvelle. Contraintes CloudKit habituelles du schéma (voir § Persistance) : propriétés optionnelles ou avec valeur par défaut, pas d'`@Attribute(.unique)`, `inverse:` sur toute relation.

Point d'attention : ne stamper que les **vraies transitions valeur → valeur différente**, jamais la configuration initiale (`nil → valeur`) — c'est déjà la règle appliquée par `DatesChangementRatio`, à conserver.

### Enregistreur livré (2026-09-23)

**Modèle** : `ChangementParametre` (`@Model`, hub SwiftData, synchronisé CloudKit) — `date`, `parametreBrut`, `typeSport`, `ancienneValeur`, `nouvelleValeur`. Le paramètre est stocké en chaîne (`ParametreSuivi.rawValue`) : un paramètre inconnu d'une version future est ignoré à la lecture au lieu de la faire échouer.

**Paramètres suivis** (`ParametreSuivi`) :

| Cas | Valeur |
| ----- | ----- |
| `ratioUnique` | g/U |
| `ratioPetitDejeuner`, `ratioDejeuner`, `ratioGouter`, `ratioDiner` | g/U |
| `facteurCorrection` | mg/dL par U |
| `ratioSport` (+ `typeSport` = `TypeSport.rawValue`) | g/U |
| `fenetreEffetSport` | heures (valeur effective, 3 h par défaut) |

La dose de lente n'est pas enregistrée : `CalculAnalyseBasale.doseHistory(lentes:)` la reconstitue depuis les injections.

**Point d'écriture unique** : `ProfilService.mettreAJour`, qui compare un instantané des paramètres avant et après la mutation. Recensement des écritures, fait avant l'implémentation :

| Écriture | Passe par `mettreAJour` | Historisée |
| ----- | ----- | ----- |
| Réglages → Ratios (`SectionRatios`, `SectionRatioCorrection`, `SectionRatiosSport`) | ✅ | ✅ |
| Onboarding (`EtapeRatiosOnboarding` réutilise `SectionRatios` + `SectionRatioCorrection`) | ✅ | ✅ (mais c'est de la configuration initiale, voir ci-dessous) |
| Bascule de mode unique ↔ par moment | ✅ | ✅ les valeurs effacées (`valeur → nil`) |
| Adoption d'un profil venu d'iCloud (`adopterMeilleureLigne`) | ❌ | ❌ — remplacement, pas modification ; l'historique arrive par CloudKit avec le profil |
| Import d'archive JSON | ❌ | ❌ — l'historique est restauré depuis l'archive |
| Réinitialisation (`reinitialiser`) | ❌ | ❌ — l'historique est supprimé en même temps |

**Règles de détection** (`HistoriqueParametres`, logique pure testée dans `HistoriqueParametresTests`) :

- `nil → valeur` : **jamais enregistré** (configuration initiale), comme `DatesChangementRatio`.
- `valeur → valeur différente` : enregistré.
- `valeur → nil` : enregistré (ratio sport retiré, ratios effacés par une bascule de mode) — la valeur en vigueur a bien changé.
- **Rafales regroupées** : les saisies d'un même paramètre espacées de moins de 5 min (fenêtre glissante, `SessionsEdition.fenetreParDefaut`) forment une seule transition, de la valeur de départ à la dernière valeur. Régler un ratio de 12 à 9 au stepper produit une ligne `12 → 9`, pas trois. Revenir à la valeur de départ dans la rafale efface la ligne. Une rafale partie de `nil` reste entièrement de la configuration initiale.
- Sessions de rafale tenues en mémoire uniquement : app tuée en cours de rafale → la ligne déjà écrite porte la dernière valeur vue, rien n'est perdu.

**Limite connue** : après une bascule de mode, les nouveaux ratios sont saisis depuis `nil` et ne sont donc pas enregistrés. La ligne `ratioUnique 12 → nil` date la bascule ; les valeurs par moment en vigueur ensuite se lisent dans le profil courant ou dans le premier changement ultérieur (`ancienneValeur`). La frise devra traiter ce cas.

**Persistance** : inclus dans l'export/import JSON (`ArchiveDonneesService`, champ `changementsParametres`, absent des anciennes archives → liste vide) et supprimé objet par objet avec le profil (`SuppressionDonneesService.supprimerProfils`). « Effacer l'historique » (événements du hub) ne le touche pas. Compteur de diagnostic : section « Synchronisation iCloud » de la page Données, ligne « Changements de réglages ».

---

## 3. Ce qui a été abandonné, et pourquoi

Le premier cadrage (2026-09-22) définissait une **période** comme un intervalle où le vecteur `(lente, ratio matin, ratio midi, ratio soir, ratio(s) sport, facteur de correction)` ne change pas. Maquettes du 2026-09-26 construites sur cette base, rejetées. Raisons :

- **Les changements sont volontairement décalés.** On change un réglage, on laisse le temps d'en évaluer l'effet, puis on en change un autre. Chaque changement coupait une période : des périodes de 2 ou 3 jours, sans aucune métrique lisible.
- **Un ajustement se fait par petits pas** (18 → 17 → 16 U en quelques jours) jusqu'à ce que la glycémie se stabilise. C'est **un seul** ajustement vécu, pas trois périodes.
- **Un changement n'est pas un verdict.** Ouvrir une période parce qu'une unité a changé, sans avoir regardé l'effet, ne dit rien.
- **Six réglages mélangés** : changer le ratio de midi coupait aussi la période vue par la lente, alors qu'aucune analyse ne dépend des six à la fois.
- **Maquettes trop denses**, peu lisibles : on ne voyait plus où se situait une donnée dans le temps ni où étaient les niveaux de charge. Le sélecteur « chronologique / par régime » ne changeait que la liste sous un graphique identique.

---

## 4. Vocabulaire

| Terme | Définition | Exemple |
| ----- | ----- | ----- |
| **Niveau de charge** | État d'**un jour** : basse / dans la référence / haute. Existe déjà (`NiveauChargeActive`, hystérésis). | « Charge active · haute » |
| **Épisode** | Suite continue de jours au **même niveau**. S'ouvre au basculement, se ferme au basculement suivant. | « Charge haute du 19 oct. au 29 nov. » |
| **Charge réelle d'un épisode** | Ce qui a été fait, en faits : séances et marche soutenue par semaine. | « 4,2 séances (5 h 10) + 1 h 30 de marche par semaine » |
| **État d'un réglage** | Pour chaque réglage, dans un épisode : en ajustement / concluant / pas assez de recul. | « Lente 16 U · concluante » |
| **Événement évaluable** | L'unité jugée pour un réglage : une nuit (lente), un repas (ratios). | « 18 nuits concluantes sur 21 » |

Le mot « régime » n'est plus employé : il mélangeait niveau de charge et période.

---

## 5. Épisodes — les frontières

**Seule règle de découpage : un changement de niveau de charge.** Un changement de réglage ne coupe jamais rien.

Pourquoi : la charge est le premier facteur qui pousse l'utilisateur à changer ses réglages. Le calcul est déjà en place, déterministe, explicable (« passage en charge haute le 19 oct. »), et stable grâce à l'hystérésis (entrée ±40 %, sortie ±25 %, 3 jours). Un épisode dure typiquement des semaines : la page ne change pas tous les quatre matins.

Le début de l'historique (moins de 5 semaines de recul, pas de référence) forme un épisode « sans référence » comme les autres.

### Le niveau est relatif, la comparaison ne doit pas l'être

Le niveau est calculé par rapport à la **référence glissante** (4 semaines, hors semaine juste avant). Exemple : de peu d'activité à 4 séances par semaine, on est « haute » pendant 4 à 5 semaines, puis la référence rattrape et on repasse « dans la référence », toujours à 4 séances par semaine. L'épisode « haute » se ferme, un épisode « dans la référence » s'ouvre.

C'est cohérent pour **délimiter** : c'est l'écart à l'habitude récente qui pousse à ajuster. Mais deux épisodes de même niveau peuvent décrire deux vies opposées (« dans la référence » à 0 séance par semaine en mars, à 4 en novembre).

**Décision (2026-09-27)** : le niveau relatif délimite les épisodes ; les épisodes passés **comparables** se retrouvent par **charge réelle**, jamais par niveau.

- Mesure de comparaison : moyenne du stock de charge active sur l'épisode, en unité absolue (la même que la référence). Jamais affichée.
- Comparable si l'écart est sous un seuil (proposition ±30 %, à calibrer).
- À l'écran, chaque épisode affiche sa charge réelle en faits, jamais en points.
- Avantage : un épisode « sans référence » devient comparable lui aussi.
- Limite connue : un changement de FC max réécrit le poids des séances passées (voir Charge active § 5), donc la charge réelle des anciens épisodes.

---

## 6. État d'un réglage dans un épisode

Chaque réglage suivi a son propre état, jugé sur **ses** événements, avec **ses** critères. C'est l'« invalidation par dimension » du premier cadrage, devenue le cœur du modèle.

| État | Quand |
| ----- | ----- |
| **Pas assez de recul** | Moins d'événements évaluables que le minimum depuis le dernier changement de ce réglage (ou depuis le début de l'épisode). |
| **En ajustement** | Minimum atteint, mais la part d'événements concluants est sous le seuil d'entrée. Tout changement de ce réglage y ramène, sans autre effet. |
| **Concluant** | Part d'événements concluants au-dessus du seuil d'entrée, sur la fenêtre glissante. |

Règles :

- **Seuils propres à chaque réglage, exprimés en comptes** (« 5 nuits sur 7 »), jamais en pourcentage : sur 6 à 8 événements, un pourcentage donne une précision qu'il n'a pas. Les réglages ne jugent ni la même chose ni le même volume (une nuit par jour ; un repas par jour et par moment ; deux ou trois repas sous ratio sport par semaine), d'où des fenêtres et des tolérances différentes (§ 7).
- **Hystérésis** : on devient concluant à un compte d'entrée, on n'en sort qu'à un compte de sortie plus bas. Sans cela l'état clignoterait à chaque loupé.
- **Garde-fou hypo, commun à tous les réglages** : deux hypos ou plus dans la fenêtre interdisent l'état concluant, quel que soit le compte. Une hypo et un pic n'ont pas le même poids : les critères ne doivent pas les échanger. Détail, définitions et exemples : « Garde-fou hypo » ci-dessous.
- **Retour possible sans changement.** Un réglage concluant qui se dégrade repasse en ajustement. La page le constate, sans chercher de cause (fatigue, maladie, capteur…).
- **Un changement de réglage remet ce seul réglage à zéro.** Les autres gardent leur état.
- **À l'ouverture d'un épisode, tous les états repartent de « pas assez de recul »** : le contexte de charge a changé, les événements de l'épisode précédent n'en disent rien. Les valeurs, elles, continuent.
- **Transition** : seulement pour la lente (quelques nuits le temps que la nouvelle dose s'installe, comme le « nouvelle dose en observation » de B1). Affichée comme un état à part, **En observation** (§ 9). Un ratio agit sur le repas même : pas de transition, y compris pour le ratio sport.
- **Transition ≠ variabilité.** Le ratio sport agit tout de suite, mais sur des repas beaucoup plus variables (activité récente, sensibilité accrue, effort différent d'une séance à l'autre) : un changement y pèse plus lourd et un résultat isolé y dit moins. Ce n'est pas un délai à attendre, c'est un bruit à absorber, d'où une tolérance plus large et un jugement par type de sport (§ 7).
- Vocabulaire à l'écran : « concluant selon vos critères », jamais « bon réglage ».

### Tâtonnement

Plusieurs changements du même réglage à la suite (18 → 17 → 16 U) forment naturellement **une seule** phase « en ajustement », puis un état concluant sur la dernière valeur si les critères sont remplis. Le détail affiche « 3 changements en 9 j ».

---

### Garde-fou hypo (décision du 2026-09-27)

**Règle** : deux hypos ou plus dans la fenêtre d'un réglage l'empêchent d'être concluant, quel que soit le compte d'événements concluants. Elle s'applique dans les deux sens : un réglage concluant qui atteint sa deuxième hypo dans la fenêtre repasse aussitôt en ajustement, sans attendre le compte de sortie.

**Pourquoi.** Les comptes d'entrée tolèrent des loupés (2 nuits sur 7, 3 repas sur 8, 2 repas sur 6). Sans garde-fou, ces loupés pourraient être tous des hypos, et le réglage s'afficherait « concluant ». Or une hypo et un pic ne pèsent pas pareil : l'hypo est le danger immédiat, et c'est ce que l'utilisateur cherche d'abord à éviter en ajustant. Les comptes ne doivent pas pouvoir échanger l'une contre l'autre.

**Ce qui compte comme une hypo**, réglage par réglage. Seuil : le seuil hypo du profil (70 mg/dL par défaut).

| Réglage | Une hypo, c'est | Ne compte pas |
| ----- | ----- | ----- |
| Lente | une nuit avec un épisode sous le seuil hypo d'au moins 15 min (ou sous 54 mg/dL) sur la fenêtre de sommeil (comptage B1, règle du 2026-10-20 — un passage bref de 1-2 relevés ne compte pas) | une hypo que B1 attribue à l'insuline rapide active au moment du creux (plus de 0,5 u, chantier 4 de B1) : la nuit est alors **non évaluable** pour la lente, ni concluante ni ratée. L'hypo reste comptée dans les métriques de l'épisode |
| Ratio d'un moment | un repas au verdict `mauvais` dont la cause est l'hypoglycémie (sous le seuil sur T+4 h) | un repas non évaluable (ajusté, contexte libre, autre événement dans la fenêtre) |
| Ratio sport | idem, sur les repas pris sous ratio sport | idem |

Pour le ratio sport, une hypo après l'effort peut venir de l'effort lui-même plutôt que du ratio. Elle compte quand même : l'état décrit ce qui s'est passé avec ce réglage dans ce contexte, pas une cause.

**Pourquoi 2 et pas 1.** Une hypo isolée arrive sans rien dire du réglage : resucrage mal dosé, effort imprévu, ou fausse hypo de compression du capteur la nuit (voir Bibliothèque, « compression lows »). Avec un seuil à 1, l'état basculerait au moindre incident, ce qui contredit la marge de loupés voulue (§ 1). Deux hypos dans une même fenêtre, c'est une répétition, plus un hasard.

**Exemples**

| Situation | Compte | Hypos | État |
| ----- | ----- | ----- | ----- |
| Lente, 7 dernières nuits | 5 concluantes, 2 ratées par dérive | 0 | concluant |
| Lente, 7 dernières nuits | 5 concluantes, 1 dérive, 1 hypo | 1 | concluant |
| Lente, 7 dernières nuits | 5 concluantes, 2 hypos | 2 | **en ajustement** |
| Ratio midi, 8 derniers repas | 6 concluants, 2 hypos | 2 | **en ajustement** |
| Ratio midi concluant, nouveau repas en hypo | la fenêtre contient maintenant 2 hypos | 2 | **repasse en ajustement** |

Seuil à calibrer (registre des paramètres à calibrer) : à surveiller en particulier pour le ratio sport, où les hypos sont plus fréquentes par nature.

---

## 7. Critères de réussite, réglage par réglage

Proposition, construite sur les verdicts existants. Aucun nouveau calcul glycémique : seulement un comptage.

### Lente — une nuit

| Nuit | Condition | Source |
| ----- | ----- | ----- |
| **Concluante** | Zone 3 classée stable (dérive dans ±30 mg/dL, ou hors ±30 mais loin des seuils) **et** aucune hypo sur la fenêtre de sommeil | B1 (classement par nuit), comptage des hypos B1/B2 |
| **Ratée** | Hypo sur la fenêtre de sommeil, **ou** zone 3 classée haute / basse | B1, B2 |
| **Non évaluable** | Zone 3 exclue par B1 pour une autre raison qu'une hypo (dîner copieux, bolus de correction, couverture < 80 %, courbe chaotique) | B1 |

Point d'attention : B1 exclut une zone avec hypo et resucrage de son calcul de pente. Ici, cette nuit est **ratée**, pas exclue : une hypo nocturne est précisément ce qu'on veut éviter.

Proposition : les 7 dernières nuits évaluables à la dose en cours, minimum 5, transition de 2 nuits après un changement de dose. **Concluante à 5 nuits sur 7**, retour en ajustement à 3 sur 7 ou moins. Le seuil le plus exigeant des trois : la nuit est la situation la plus contrôlée (à jeun, sans effort, loin des repas), un loupé y dit donc davantage.

**Même dose, deux seuils : la tendance basale (B1) et C1 (décision du 2026-10-20).** B1 juge la dose de lente sur ses 5 dernières nuits valides, avec un verdict dès 3 (`ConstatVerdictBasale.nuitsMinimales`) : elle réagit vite et répond à « est-ce que mes nuits vont bien en ce moment ? ». C1 demande 7 nuits, concluante à 5, minimum 5, 2 nuits d'observation après un changement, et repart de zéro à chaque épisode de charge : elle répond à « cette dose a-t-elle fait ses preuves dans ce contexte ? ». Les deux seuils sont **conservés** ; on peut donc lire « Stable » côté tendance basale et « 4 nuits sur 5 nécessaires » côté C1 pour la même dose. La feuille « Critères » le dit en une phrase, sous les seuils, chiffre lu dans la constante de B1 :

> La tendance basale juge la même dose dès 3 nuits pour suivre vos nuits au jour le jour ; ici, la dose doit faire ses preuves dans l'épisode de charge en cours, d'où plus de nuits.

### Ratio d'un moment (matin, midi, soir) — un repas

| Repas | Condition | Source |
| ----- | ----- | ----- |
| **Concluant** | Verdict R1 `bon` (pas d'hypo sur T+4 h, et pic ≤ 180 ou retour ≤ 180 sous 2 h avec pic < 220) | `VerdictGlycemique` |
| **Raté** | Verdict R1 `mauvais` (hypo ou pic élevé) | idem, `RaisonMauvaisVerdict` |
| **Hors compte** | Verdict R1 `moyen` : aucune hypo, sortie au-dessus de 180 **mais revenue en cible** dans la fenêtre (retour après 2 h, ou pic entre 220 et 250) | décision du 2026-09-27, voir ci-dessous |
| **Non compté** | Verdict indéterminé, exclu à la main, contexte libre, ajusté, courbe qui ne mesure pas que ce repas (autre repas, correction, resucrage, sport, insuline active) | règle commune avec R1 (`CalculEligibiliteRepas`, voir doc R1 « Repas pollués par leur fenêtre ») |

Proposition : les 8 derniers repas évaluables de ce moment, minimum 5 (même garde-fou que le mining R1). **Concluant à 5 repas sur 8**, retour en ajustement à 3 sur 8 ou moins. Plus tolérant que la lente : l'estimation des glucides ajoute son propre bruit à chaque repas.

**Verdict `moyen` (décision 2026-09-27).** Vérifié dans `AssembleurReponseRepas.verdict` : un repas jamais revenu en cible est déjà `mauvais` ; `moyen` désigne donc un pic au-dessus de 180 **qui est redescendu**. Il n'est compté ni concluant ni raté en V1 : il ne rentre pas dans la fenêtre. Le compter comme raté (180 est une hyperglycémie) resterait défendable ; un réglage pour l'inclure pourra venir plus tard, mais chaque exclusion rétrécit l'entonnoir de données, à peser à ce moment-là.

### Ratio sport (par type de sport) — un repas sous ratio sport

Repas pris dans la fenêtre d'effet d'une séance de ce type, avec un ratio sport renseigné pour ce type : exactement les repas que R1 écarte de son mining. Même règle commune et même jugement que ci-dessus (verdict R1 par repas).

**La séance qui déclenche le ratio sport n'est pas une pollution** (décision du 2026-10-20) : sinon aucun repas après le sport ne serait jamais jugé. Une autre séance, un autre repas, une correction ou un resucrage dans la fenêtre écartent toujours le repas.

Proposition : les 6 derniers repas sous ratio sport **du même type de sport**, minimum 4. **Concluant à 4 repas sur 6**, retour en ajustement à 2 sur 6 ou moins. Tolérance la plus large des trois, pour la variabilité décrite au § 6 ; le garde-fou hypo reste le même. Avec environ 3 séances par semaine, cet état restera souvent « pas assez de recul » : c'est honnête.

### Hors V1

- **Facteur de correction** : pas demandé pour cette page. Les issues des corrections restent dans B3.
- **Glucides pré-sport et resucrages pendant l'effort** (verdicts S1) : ils jugent une prise de glucides, pas un réglage.

---

## 8. Ce qui s'affiche pour un épisode

### Valeur retenue d'un réglage

Pour chaque réglage, la valeur qui compte **le plus d'événements concluants** dans l'épisode, avec son compte : « Lente 16 U · 18 nuits concluantes sur 21 ». Égalité : la plus récente.

Si aucune valeur n'a rempli les critères : « aucune valeur n'a rempli vos critères », avec la dernière valeur en place. C'est un fait, pas un reproche.

Le compte reste affiché : il distingue « la plus longtemps concluante » d'un classement de qualité. Les autres valeurs de l'épisode viendront plus tard, sur une page dédiée à l'historique des réglages.

### Métriques de l'épisode (tous réglages confondus)

Toujours en taux, jamais en compteurs bruts :

- temps dans la cible (%) ;
- score quotidien moyen (100 − GRI) ;
- resucrages par jour ;
- couverture CGM (%), en qualité de la donnée, pas en résultat.

Chaque métrique sous son seuil de lisibilité s'affiche « pas assez de recul » plutôt qu'un chiffre fragile.

---

## 9. Affichage — maquette validée le 2026-10-18

Règles d'interface appliquées : Vouvoiement, grands titres de section, aucun texte d'explication superflu.

### Écran 1 — page « Charge et glycémie »

| Section | Contenu |
| ----- | ----- |
| **En ce moment** | Carte de l'épisode, qui remplace la carte « Charge active » actuelle : niveau, « Depuis le … · N jours », badge **Nouvel épisode** pendant 7 jours. Trois chiffres : écart à la référence, séances par semaine, marche par semaine. Si l'épisode est nouveau, une ligne « Avant : <niveau>, <durée> ». |
| **Chronologie** | Graphique existant, inchangé (charge par semaine face au score GRI). Aucun réglage dessus. |
| **Vos réglages** | Trois sous-sections : Lente, Repas (matin, midi, soir), Activité physique (un ratio par type de sport). Une ligne par réglage : icône d'état, nom, une ligne de compte (« 6 nuits concluantes sur 7 », « 4 nuits sur 5 nécessaires »), valeur à droite avec la mention « actuel ». |
| **Les fois précédentes** | Une ligne par épisode à charge comparable (dates, séances et marche par semaine), puis une ligne repliée « Autres épisodes » avec leur nombre. Sans épisode comparable : « Aucun épisode comparable pour l'instant. » |

### Écran 2 — un épisode passé

| Section | Contenu |
| ----- | ----- |
| **L'épisode** | Niveau, période, trois chiffres : durée, séances par semaine, marche par semaine. |
| **Vos réglages à l'époque** | Une seule phrase : « Valeur la plus concluante de l'épisode. » Mêmes trois sous-sections. Par ligne : nom, puis « 15 U · 18 nuits sur 21 », et « Auj. 16 U » en petit à droite. Réglage sans valeur concluante, pas assez de recul ou valeur non enregistrée : **icône en pointillé** (lignes grisées essayées puis retirées). |
| **Résultats** | Temps dans la cible, score moyen, resucrages par jour, couverture CGM. |

### Écran 3 — un réglage (ici la lente)

| Section | Contenu |
| ----- | ----- |
| **Dose actuelle** | Valeur en grand, état, « Depuis le … » ou « Nouvelle dose le … ». |
| **Nuits de l'épisode** | Une pastille par nuit à la dose actuelle : concluante, dérive, hypo, observation (pointillé bleu), à venir. |
| **Doses déjà utilisées** | Une ligne par dose et par épisode : dose, niveau de charge et période, compte à droite (« 18/21 nuits »). Période trop courte : ligne grisée, « trop court ». Chaque ligne ouvre l'épisode. |

L'écran d'un ratio suit la même structure, avec des repas à la place des nuits.

### États affichés

| État | Icône | Sens |
| ----- | ----- | ----- |
| Concluant | coche verte | § 6 |
| En ajustement | flèches orange | § 6 |
| **En observation** | horloge bleue | nouvelle dose de lente, pendant ses 2 nuits de transition (§ 6) : elles ne comptent pas encore |
| Pas assez de recul | sablier gris | le compte dit combien d'événements manquent |

### Arbitrages pris avec la maquette

- Graphique : pas de repère d'épisode (variante « avec teinte » maquettée, non retenue par défaut).
- Épisodes à charge différente : repliés dans « Autres épisodes ».
- Badge « Nouvel épisode » : 7 jours.
- Pas de mention de bas de page (« faits observés… ») : retirée à la demande de l'utilisateur.
- Sections « Temps dans la cible selon la charge du jour » et « Dérive basale selon la charge » : **supprimées** le 2026-10-18 (écran et calcul), à la demande de l'utilisateur. Elles regroupaient par niveau (étiquette relative) et mélangeaient des réglages différents, ce que les épisodes évitent.

Aujourd'hui (oct. 2026) : un seul épisode réel, beaucoup de « pas assez de recul », aucun épisode comparable. Comportement attendu.

---

## 9 bis. Implémentation V1 (2026-10-18)

- **Calcul** : `CalculEpisodesCharge` (pur, testé dans `CalculEpisodesChargeTests`). Épisodes = suites de jours au même niveau dans le contexte de charge active ; comparaison sur la moyenne absolue du stock (`chargeMoyenne`, ±30 %).
- **Repas** : règle commune avec R1, `CalculEligibiliteRepas` (2026-10-20), testée dans `CalculEligibiliteRepasTests`.
- **Faits** : `ChargeurEpisodesCharge`. Lente = une nuit B1 (`NightChartData`, qui expose désormais `hyposNonExpliquees` et `enCours`). Ratios = un repas R1 (mêmes exclusions que le mining, verdict `moyen` non évaluable) ; le ratio sport du type de séance quand il était en vigueur. Valeur d'un ratio à une date reconstituée depuis `ChangementParametre` ; inconnue avant un changement antérieur au 23 sept. 2026.
- **Service** : `CorrelationChargeTIRService`, qui fait tourner B1 sur tout l'horizon (90 nuits) et calcule épisodes et corrélation dans la même tâche.
- **Vues** : `VuesEpisodesCharge.swift`, branchées dans `PageCorrelationChargeGlycemie`. La carte « Charge active » est remplacée par la carte de l'épisode ; sources et FC max passent dans le mode d'emploi du graphique.
- **Critères à l'écran** : bouton « i » (barre de navigation de la page, d'un épisode et d'un réglage) → feuille « Critères » : définition d'un épisode, de « concluant », seuils de chaque réglage, écart avec la tendance basale, garde-fou hypo, observation, seuils des résultats. Tous les chiffres sont lus dans les constantes du calcul (et le seuil d'hyper dans le profil), jamais recopiés.
- **Listes** : apparence habituelle partout. Les lignes grisées sur fond plus sombre (maquette v3) ont été retirées après essai sur l'iPhone ; seule l'icône en pointillé signale une valeur qui ne remplit pas les critères.
- **Seuils de lisibilité des résultats** : temps dans la cible et score à partir de 3 jours avec CGM, resucrages par jour à partir de 7 jours (registre).

**Limites connues**

- **Horizon de 90 jours** (`CalculChargeActive.horizonJours`) : un épisode plus ancien n'est pas vu. **Décision du 2026-10-19 : conservé pour l'instant.** Au-delà de 90 jours de saisie, les premiers jours sortent de la fenêtre ; les données restent dans le hub, seule la page ne remonte pas plus loin. À revoir si un épisode comparable utile date de plus de 3 mois (charge saisonnière). Allonger ne demande que du calcul (B1 sur plus de nuits, contexte de charge plus long).
- Bascule de mode ratio unique ↔ par moment : les repas sont rangés selon le mode actuel.

---

## 10. IA / ML — décision du 2026-09-27

**Pas pour la V1.** Question posée sérieusement, pas une exclusion de principe.

- **Apprentissage supervisé** (prédire la réussite) : il faudrait des centaines d'exemples étiquetés. Un utilisateur produit quelques dizaines de changements de réglage par an. Un modèle entraîné sur si peu apprendrait du bruit.
- **Clore les épisodes sur les résultats** (taux de réussite sous un seuil) : circulaire. Des épisodes définis par « ça marchait » sont tous bons par construction, et leur comparaison ne dit plus rien. La clôture ne dit pas non plus pourquoi (réglage, fatigue, capteur).
- **Explicabilité** : « le modèle pense que ça marchait », sans raison lisible, est la fausse confiance que le projet désigne comme le vrai risque.

Ce qui reste crédible plus tard :

- **Détection de rupture** sur une série (par exemple la part de nuits concluantes) : plutôt de la statistique que du ML, fonctionne sur une seule série. Pourrait compléter les états : « tes nuits ont changé de comportement autour du 12 oct. ».
- **Foundation Models on-device** pour rédiger un résumé, tagué « contenu généré par IA ».

Condition pour y revenir : 6 à 12 mois de données **et** des cas réels où les règles du § 6 se trompent de façon démontrable. Les états calculés par règles produisent justement les données étiquetées dont un futur modèle aurait besoin.

---

## 11. Ce que la page ne fait pas

- Pas de classement « meilleure période » ni de mise en avant d'un réglage. « Concluant » veut dire « a rempli vos critères », rien de plus.
- Pas d'extrapolation ni de prédiction : uniquement ce qui a été observé.
- **Aucune suggestion de dose, jamais.** Afficher « la lente à 16 U a compté 18 nuits concluantes sur 21 en charge comparable » est un fait. Écrire « passe à 16 U » est un conseil thérapeutique, hors de ce que l'app est autorisée à être.

---

## 12. Questions ouvertes

- Verdict R1 `moyen` : hors compte en V1 (§ 7). Un réglage pour l'inclure comme raté, plus tard ?
- Seuils des états (fenêtres, minimums, 70 % / 50 %) : propositions à calibrer, voir [Paramètres à calibrer](../architecture/Diaviz%20—%20Paramètres%20à%20calibrer.md).
- Seuil de charge comparable (±30 %) : trop large mélange des vies différentes, trop étroit ne retrouve jamais rien.
- Durée de transition de la lente : 2 nuits est une hypothèse.
- Seuils de lisibilité des métriques d'épisode (TIR, resucrages par jour).
- Bascule de mode ratio unique ↔ par moment (limite connue de l'enregistreur, § 2) : comment la présenter dans l'état des ratios.
