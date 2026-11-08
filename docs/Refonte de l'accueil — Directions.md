# Refonte de l'accueil — Directions

> Pistes de réflexion, notées le 2026-11-08. **Rien n'est décidé ni développé.** Décision du moment : on ne touche pas aux cartes « Nouvelles tendances » ni à l'accueil actuel.

**Question de l'écran** : « Que s'est-il passé depuis ma dernière visite, et qu'est-ce qui demande mon regard ? »

## Constat sur l'accueil actuel
- Tout a le même poids : score, activité et glucides occupent chacun une grande carte, alors que ce qui compte (un repas à revoir, un sport à importer) est enfoui.
- Le retard d'environ 3 h du capteur n'est dit nulle part : l'app est rétrospective, l'écran ne le montre pas.

## Les directions

### Direction 1 — La journée comme une frise (retenue, avec la 2)
- Titre « Aujourd'hui », date, et « glycémie lue jusqu'à 11:26 ».
- Score de la veille en une seule ligne en haut.
- Frise du plus récent au plus ancien : import à faire, repas, séance, lente, nuit.
- Chaque repas ou séance porte sa mini-courbe.
- Un repas dont la réponse n'est pas prête se repère à son icône en pointillé : « Sa courbe arrive vers 13:40 ».
- La pile de cartes disparaît : ses cartes deviennent des lignes de la frise.

### Direction 2 — Une seule grande courbe (retenue, avec la 1)
- Les dernières 24 h dans un seul graphique, lignes d'hypo et d'hyper, repères repas, séance et lente.
- Zone grisée à droite pour les 3 dernières heures « non reçues ».
- Dessous : quatre chiffres (dans la cible hier, score hier, glucides en moyenne, activité sur 7 jours), puis une liste « À regarder ».
- La courbe de 24 h n'existe pas encore dans l'app : c'est un chantier à part.
- Avec peu de données, la courbe est trouée : il faudra dire pourquoi.

### Direction 3 — Un tri par ce qui demande le regard (non retenue)
- Trois blocs en listes natives : « À regarder », « Réponses disponibles », « En ordre ».
- Quand tout va bien, l'écran est presque vide.
- La moins coûteuse, mais la moins différente de l'existant.

## Où les mettre
Un quatrième onglet a été envisagé, mais il créerait un deuxième accueil. Le Journal reste l'endroit où l'on saisit, l'accueil l'endroit où l'on lit.

**Proposition : l'accueil devient courbe + frise, en deux étages.**
1. Haut de page : la courbe des dernières 24 h (direction 2).
2. Dessous : la frise (direction 1), avec les cartes d'insight devenues des lignes.

Le reste de l'accueil actuel :
- Score, activité, glucides : bandeau de quatre chiffres sous la courbe.
- Ratios : onglet Analyses, où ils ont déjà leur page. La frise remonte un verdict quand il change (« Ratio petit déjeuner : comparaison disponible »).
- « Aperçu du jour » : absorbé par la courbe.

Ce qu'on perd : un accueil plus long, et la carte « Analyse des ratios » moins visible.

**Alternative moins risquée** : garder l'accueil tel quel et ouvrir un grand écran « Aujourd'hui » depuis le titre « Nouvelles tendances », sans nouvel onglet. La pile de cartes resterait.

## Décisions ouvertes
1. Remplacer l'accueil par courbe + frise, ou ajouter la frise derrière le titre ?
2. Cadrer la courbe de 24 h comme un chantier à part, ou commencer par la frise seule ?

Avant tout développement : maquette complète de la direction retenue, avec les trois cas limites (jour presque vide, juste après un changement, historique riche).

## Autres pistes sur les cartes (non décidées)
- Fusionner « Repas à revoir » et la courbe du même repas en une seule carte, avec une pastille « À revoir ».
- Point bleu sur les cartes pas encore ouvertes, et compteur « 3 nouvelles » au lieu du total.
- Séance : durée dans le titre, variation (−55) écrite sur la courbe au lieu du pic.
- Journée chargée : à partir de 3 repas, une carte « 3 repas aujourd'hui » avec trois mini-courbes.
- Notification à l'heure du repas + 4 h : l'app n'a aucune tâche de fond, à décider explicitement.
