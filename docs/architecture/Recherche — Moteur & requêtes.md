# Recherche — Moteur & requêtes
>   Interroger ses propres données par critères combinés : « ce repas, comment avait-il été géré la dernière fois ? », « quelles séances de course sont parties de 180 et ont demandé un resucrage ? ». Socle **déterministe**, réutilisé tel quel plus tard par le chat LLM.  

**Statut** : 🟢 Lots 1 et 2 livrés (8 septembre 2026) · **Branche** : `feature/recherche` · **Voir aussi** : « Recherche — Comment ça marche (schéma) », « Dette technique — identifiée, à traiter », « Index des analyses »

---

## Où on en est
| Lot | Contenu | Statut |
| ----- | ----- | ----- |
| **1** | Chronologie unifiée, modèle de requête, moteur, synthèse, les trois questions en tests | <p>🟢 </p><p>**Livré**</p> |
| **2** | Constructeur de corpus, écran de facettes, balayage + dépliage, synthèse à l'écran, placeholder du chat | <p>🟢 </p><p>**Livré**</p> |
| **3** | Tool Foundation Models + chat | 🔵 Non commencé — maquettes validées |
| <p>**Raison de l'ordre, inchangée**</p><p> : si le lot 3 déçoit — modèle 3B trop faible, Apple Intelligence indisponible, tool calling non fiable — les lots 1 et 2 restent intacts et utiles. L'inverse n'est pas vrai.</p> |  |  |
L'onglet ouvre sur le **chat** (placeholder assumé, modèle non branché) et bascule vers la recherche par critères, dans les deux sens en un tap.

---

## Pourquoi
- L'onglet était un **placeholder vide** depuis avril 2026.
- Les questions réelles sont des **filtres**, pas des analyses. Elles n'ont pas besoin de significativité statistique : montrer un seul repas passé identique est déjà utile. C'est ce qui a rendu la recherche faisable dès trois semaines de saisie, alors que les analyses restantes attendent du volume.
- Le chat aura besoin de cette couche de toute façon. L'écrire seule d'abord, c'est pouvoir la **tester sans le modèle**.
---

## Principe central — la requête est une valeur
Une **requête** est une donnée qui décrit _quoi_ chercher, jamais _comment_ : un sujet, des critères cumulés en ET, un mode de présentation.

Trois producteurs, un seul moteur : l'**écran** de facettes, les **tests**, et demain le **Tool du chat**. Le moteur ne sait pas lequel l'appelle.

>   Le piège évité : avec des fonctions à paramètres, le chat exigerait une couche de traduction par fonction, et chaque nouveau critère se répercuterait partout. Ici il n'ajoute qu'un cas d'énumération — les quatre critères ajoutés en fin de lot 2 l'ont vérifié.  

- **Un critère par valeur retenue**, jamais un critère portant une liste : retirer « Frites » ne touche pas « Club sandwich », et la barre de facettes est le rendu direct du tableau de critères.
- **Un critère hors sujet est refusé à l'ajout**, pas accepté puis ignoré au fond du moteur. Le moteur l'écarte quand même s'il en reçoit un — ceinture et bretelles, en prévision des requêtes venues du chat.
- **Le seuil de synthèse n'est pas dans la requête.** C'est un réglage d'affichage : une requête ne doit pas changer parce qu'un curseur a bougé dans les Réglages.
⚠️ La **sérialisation** des recherches enregistrées n'est toujours pas faite — un des types réutilisés (la section de journal) n'est pas encodable.
---

## Moteur
Calculateur **pur** : ne lit aucun magasin, ne connaît pas son appelant, rend le même résultat pour la même entrée.

### Deux points d'entrée, une seule implémentation par critère
- `preselection…`  s'applique aux **faits bruts**, avant hydratation. Elle ne répond qu'aux critères de réduction — c'est son intérêt : l'appelant s'en sert pour n'hydrater que les survivants.
- `executer`  s'applique au corpus hydraté et applique **tous** les critères. C'est la spécification du filtrage : correcte seule, même sans présélection.
Les deux partagent `evaluerStocke` . Un test vérifie qu'elles retiennent exactement les mêmes éléments : un critère n'est écrit qu'une fois, jamais réimplémenté d'un côté puis de l'autre.
### Le piège qui impose tout ça
`ReponseGlycemiqueSport` n'est pas persistée — glycémie de départ, delta et points CGM sont recalculés à chaque affichage. `ActiviteSportive.dateFin` se calcule avec les pauses. La **section de journal** d'un repas se déduit de son heure et des horaires du profil, avec traitement circulaire du passage minuit. Aucun de ces critères n'est exprimable en prédicat.

À l'inverse, côté repas, `verdictPersiste`, `ratioEffectifPersiste`, les contextes de vie et les ajustements **sont** stockés.

### L'étage de réduction en base n'est pas construit
Le cadrage annonçait une requête SwiftData réduisant le corpus. Le moteur applique **les deux étages en mémoire**, et le raccourci n'existe pas : il doit être la spécification du filtrage, donc correct sans magasin, donc testable. Construire en plus le prédicat créerait un second endroit où un critère peut être mal appliqué, pour gagner des millisecondes.

La frontière reste **déclarée sur chaque critère** : le jour où le volume le justifie, l'appelant traduit sans que le moteur bouge.

### Justification de la correspondance
Chaque occurrence porte **les critères qui ont mordu et la valeur constatée** — « Départ 160–200 — 178 », « Club sandwich poulet », « 1 resucrage ».

Rien d'autre dans l'app ne justifie un affichage, parce que rien d'autre n'est une requête. C'est ce qui permet de faire confiance à un résultat — et, quand le chat produira les requêtes, de voir qu'il n'a pas filtré autre chose que ce qu'on croyait.

### Comportements tranchés
- **Donnée absente ≠ hors critère.** Une séance sans couverture CGM est **écartée** d'un critère de glycémie, jamais supposée conforme ; idem sans IOB renseigné. Elle reste comptée au dénominateur et cherchable sur ses critères stockés.
- **Recherche d'aliment en sous-chaîne**, plus permissive que le regroupement de `CalculRepasARevoir`  : un résultat de recherche est jugé par l'utilisateur qui le voit, un regroupement sert de prémisse à une inférence.
- **Tri par date décroissante.**
- **Dénominateur explicite.** Le corpus reçu ne contient que les survivants de la présélection : sa taille afficherait « 1 sur 1 » là où il faut lire « 1 sur 6 ». Le moteur accepte donc un total fourni par le constructeur depuis le hub entier.
---

## Constructeur de corpus
Seul point de contact de la chaîne avec le magasin.

1. **Présélection sur les faits bruts** — gratuit.
2. **Hydratation des seuls survivants** — relire le CGM est la seule opération chère.
Aux volumes actuels l'ordre ne change rien. Il est posé parce que l'inverse devient impraticable sans qu'on s'en aperçoive, et se corrige mal une fois l'écran construit dessus.
Les faits du hub sont lus **en une fois** sur l'enveloppe commune des fenêtres, puis découpés en mémoire — plutôt que N allers-retours.

**Simplification assumée** : les survivants sont hydratés complètement, sans regarder quels critères la requête porte. L'affichage réclame de toute façon la courbe et la chronologie de ce qui est retenu ; le raffinement n'économiserait que sur les candidats écartés à l'étage 2, une minorité.

---

## Facettes par sujet
Une **facette** est un critère isolé, ajoutable et retirable seul. La feuille d'ajout est une **liste fermée**, jamais un champ libre — c'est ce qui supprime l'ambiguïté à la source.

| Sujet | Facettes | Étage |
| ----- | ----- | ----- |
| **Repas** | aliment, glucides, verdict | réduction |
|  | contexte de vie (« Restaurant », « Voiture »…) | réduction |
|  | dose ajustée (toutes raisons, ou une précise) | réduction |
|  | moment de la journée | **hydratation** |
| **Sport** | type, structure d'effort, intensité, durée | réduction |
|  | glucides pré-sport, insuline active au départ | réduction |
|  | glycémie de départ | **hydratation** |
|  | resucrage pendant (intention optionnelle), correction pendant | **hydratation** |
| **Commun** | période | réduction |
### Trois formes de saisie
- **Liste fermée** — type de sport, structure, intensité, verdict, moment, intention de resucrage, raison d'ajustement.
- **Plage réglable** — glycémie de départ, durée, glucides, IOB. Deux curseurs qui **se poussent l'un l'autre** au lieu de se bloquer ; un curseur qui refuse d'avancer se lit comme cassé. Des tranches figées avaient été essayées d'abord et se sont révélées trop larges à l'usage : « 180 à 400 » ne répond pas à « je suis à 178 ».
- **Recherche dans l'historique** — aliments et contextes, avec leur nombre d'occurrences, triés par fréquence. On ne propose que ce qui existe : une valeur jamais saisie ne peut rien remonter, et le compteur dit tout de suite si ça vaut le coup.
---

## Vocabulaire tranché
- **Correction** = insuline. Injection rapide, `Repas.doseCorrection`  . La lente n'en est pas une.
- **Resucrage** = prise de glucides. Entité `Resucrage`  et son `IntentionResucrage`  .
Deux entrées distinctes dans la feuille, chacune avec son sous-titre (_insuline rapide_ / _prise de glucides_). En langage courant « j'ai dû corriger pendant l'effort » désigne presque toujours un resucrage — exactement l'ambiguïté qu'une liste fermée supprime et qu'un modèle 3B trancherait silencieusement.
---

## Chronologie unifiée
Le concept d'« événement sur une courbe » existait **deux fois**, ancré sur son écran de chaque côté.

**Livré** : un type neutre dans un module neutre, portant une **date absolue** (le relatif se calcule à l'affichage), un genre **resucrage typé par son intention**, et une **quantité séparée du libellé**. Sans cette dernière, il fallait redécouper une chaîne française pour retrouver un nombre — la règle qu'on s'est donnée pour le chat était déjà violée par notre propre code.

`CalculRepasARevoir.evenements` est devenue une façade.

### Ce qui n'a pas été fusionné
`EvenementActivite` et la frise de séance sont **inchangés** : la frise porte des notions qui lui sont propres (passage en pause, verdict de la prise), et sa refonte n'apportait rien au moteur. À reprendre si la vue dépliée en a besoin.

### Règle de fenêtre
**La fenêtre est définie par l'objet observé, pas par les événements.** Tout ce qui tombe dedans s'affiche ; on n'élargit jamais pour attraper un fait de plus.

L'objet observé est **exclu** de sa propre chronologie par le constructeur — l'appelant le représente déjà. Mais il est **reconstruit à l'affichage** dans la liste dépliée : sans lui, on voyait le resucrage de 18h38 sans le repas de 12h30 qui ouvre la fenêtre.

---

## Règle du dénominateur
| Cas | Rendu |
| ----- | ----- |
| `n = 0`  | Message explicite, jamais un écran vide |
| `n < seuil`  | <p>**Pas de moyenne calculée.**</p><p> Les cas listés, avec un bandeau qui dit pourquoi — sans lui, demander la synthèse et voir la liste se lit comme un bouton cassé</p> |
| `n ≥ seuil`  | Synthèse, chaque moyenne collée à son effectif |
| <p>**Seuil : 5**</p><p>, réglable dans Profil → Seuils.</p> |  |
**Chaque moyenne voyage avec son dénominateur réel**, qui n'est pas l'effectif du résultat : la glycémie de départ ne se moyenne que sur les séances **couvertes par le CGM**, les glucides que sur celles **ayant eu une prise** — moyenner sur l'ensemble diluerait avec des zéros. Une séance compte **une fois par intention** présente, la question étant « sur combien de séances », pas « combien de prises ».

Une case sans donnée affiche un tiret, jamais un zéro qui se lirait comme une mesure.

⚠️ La synthèse n'existe que pour les **séances**. Aucune des trois questions n'en demande sur les repas.

---

## Présentation
Un contexte de recherche n'est pas un contexte de consultation : **on compare**.

- **Échelle commune, affichée.** Une mini-courbe auto-cadrée sur ses propres valeurs est un mensonge visuel dès qu'on en met deux côte à côte. La courbe **dépliée**, elle, est auto-cadrée : on lit un cas, on ne le compare plus.
- **Alignement en colonnes.** Côté repas, la colonne montre le **pic teinté par le verdict**, pas les glucides : la quantité est une entrée, pas un résultat.
- **Repères hypo et hyper** en pointillés sur la courbe dépliée, pris sur les seuils du profil.
- **Icônes au sommet des repères d'événement** : des traits colorés sont anonymes, la couleur seule ne dit pas de quoi il s'agit.
- **Dépliage sur place**, plusieurs à la fois, **sans animation** — changer la hauteur d'une ligne au milieu d'une liste saccade quoi qu'on tente. Un morph entre la mini-courbe et le grand tracé a été essayé puis retiré.
- **Contrôles flottants en Liquid Glass** au-dessus de la liste : pastilles de critères et bascule cas/synthèse sont une couche de contrôle, pas de contenu. Réunies dans un `GlassEffectContainer`  — plusieurs surfaces de verre indépendantes se rendent en panneaux plats. Teinte violette, accordée à la carte de présentation.
- **Pas d'état vide** : sans critère, on voit tout l'historique du sujet. Filtrer, c'est retrancher.
---

## Tests
**341 au total**, dont le **premier harnais SwiftData** de la suite : un conteneur en mémoire couvre le constructeur de corpus et le calcul de courbe à la demande.

>   Le schéma doit être déclaré **en entier** et non type par type : un `Aliment` porte trois relations inverses, et un conteneur partiel échoue à l'ouverture. Coûteux à découvrir.  

Les trois questions restent les critères d'acceptation :

| # | Question | Ce qu'elle exerce |
| ----- | ----- | ----- |
| **1** | Club sandwich avec frites : connu ? géré comment ? | Cumul de deux critères d'aliment, sous-chaîne, dose / ratio / verdict, tri, cas « jamais mangé » |
| **2** | Course continue d'une heure, départ à 180 : resucrage ? | Cinq critères sur les deux étages, jointure temporelle, séance sans CGM écartée mais comptée |
| **3** | Moyenne des séances de tennis, départ et préventifs maintien | Seuil, dénominateurs distincts par moyenne, comptage par intention |
---

## Arbitrages tranchés
| Question | Décision |
| ----- | ----- |
| Seuil de bascule cas → synthèse | 5, réglable dans Profil → Seuils |
| « Correction » dans une question sport | = insuline. Le resucrage est une facette distincte |
| Plages | Réglables au curseur, pas de tranches figées |
| Tri des résultats | Date décroissante |
| Compteur « sur N enregistrés » | Affiché |
| Événements sur la chronologie | <p>**Tous**</p><p>, dans la fenêtre observée, objet observé compris à l'affichage</p> |
| Dépliages simultanés | Plusieurs, sans limite |
| Animation du dépliage | Aucune |
| Écran d'accueil de l'onglet | Le chat, avec bascule vers la recherche |
| Resucrages sur la carte d'accueil « Repas à revoir » | <p>**Non**</p><p> — ce serait un changement de produit, pas une extraction</p> |
---

## Hors périmètre
- Périodes en langage naturel, tri par pertinence, agrégation croisant les sujets, synthèse sur les repas.
- Curseur parcourable sur la courbe dépliée (existe sur la frise sport, non fusionné).
---

## Garde-fous pour le lot 3
Posés d'avance parce qu'ils contraignent la conception des lots 1 et 2 :

- **Le modèle ne doit jamais pouvoir écrire un chiffre.** Sa sortie ne contient que de la prose de liaison et des identifiants ; les widgets vont chercher les valeurs dans le hub. On passe de « on lui a dit de ne pas » à « il n'a pas la donnée » — seule version vérifiable en test. La quantité portée à part du libellé va dans ce sens.
- **Le bandeau de requête est le garde-fou visuel.** Les maquettes validées montrent, sous chaque réponse, les critères que le modèle a construits, et un lien « ouvrir dans la recherche » qui rend la main sur la même requête. Le chat ne fait que remplir une `RequeteRecherche`  .
- **Les Tools retournent des identifiants et un compte, jamais des données.** La fenêtre de contexte du modèle on-device est de l'ordre de 4 k tokens ; une seule courbe CGM la saturerait.
- **Le refus est déterministe.** Une question prescriptive est classée avant génération et reçoit une réponse figée. Jamais délégué au modèle.
- **Une question → un Tool → un widget.** Le chaînage multi-Tools n'est pas fiable à cette taille de modèle.
- **Vouvoiement** sur l'écran du chat : c'est l'app qui s'adresse à quelqu'un, ce n'est plus un libellé d'interface.
- Le chat est le **premier composant non auditable** de Diaviz. Tout le reste est du Swift déterministe, testé, recomptable à la main.
