# Recherche — Comment ça marche
>   Version lisible sans contexte technique. Le détail des décisions est dans « Recherche — Moteur & requêtes ».  

---

## L'hydratation, en une phrase
**Reconstruire les valeurs qui ne sont pas rangées dans le hub, pour pouvoir répondre à une question qui porte dessus.**

Ce n'est pas un enrichissement d'affichage. C'est une condition pour que certains critères soient seulement _répondables_.

### Pourquoi il faut le faire
Le hub range les **faits bruts** : l'heure d'un repas, ses aliments, sa dose. L'heure d'une séance, son type, sa durée. Les mesures CGM, une par une.

Il ne range **pas** ce qui se déduit de ces faits :

| Ce qu'on cherche | Est-ce rangé ? |
| ----- | ----- |
| Type de sport, structure d'effort, durée | 🟢 Oui, tel quel |
| Aliments d'un repas, dose, verdict, ratio | 🟢 Oui, tel quel |
| **Glycémie de départ d'une séance** | 🔴 Non — se recalcule depuis les mesures CGM |
| **Courbe glycémique** | 🔴 Non — idem |
| **« A eu un resucrage pendant l'effort »** | 🔴 Non — aucun lien stocké entre une séance et un resucrage, ça se déduit des horaires |
| **Moment de la journée d'un repas** | 🔴 Non — se déduit de l'heure + des horaires du profil |
| <p>Sans hydratation, la question « quelles séances sont parties de 180 ? » est </p><p>**sans réponse possible**</p><p> : la valeur n'existe nulle part, il faut la refabriquer.</p> |  |
### Pourquoi on ne range pas tout, une bonne fois
Principe du hub, posé dès le départ : **un hub, des dérivations**. Ce qui se recalcule n'est pas stocké en double.

Une valeur stockée en double devient fausse dès que sa source bouge. Si l'heure d'un repas est corrigée, ou si les horaires de journée dans le profil, tout ce qui en découlait devrait être réécrit partout. Recalculer coûte quelques millisecondes ; désynchroniser coûte des bugs invisibles.

### Pourquoi l'ordre compte
L'hydratation est **la seule chose chère** de la chaîne : reconstruire la réponse d'une séance demande d'aller chercher ses mesures CGM.

D'où l'ordre du schéma : on écarte d'abord sur ce qui est déjà rangé (gratuit), et on n'hydrate que les survivants. « Course, en continu, environ une heure » ramène mille séances à quatre-vingts — on en hydrate quatre-vingts, pas mille.

C'est pour ça que les deux tris sont séparés dans le code, alors qu'aujourd'hui, avec six séances, ça ne changerait rien.

---

## La frontière des 45 jours
### Ce qui se passe aujourd'hui
Vérifié dans `RepasService` :

1. **Les mesures CGM sont bien stockées**, une par une, dans le hub (`GlucoseReading`  ), et ne sont jamais purgées. Seul « Supprimer les données » les efface.
2. **Ce qui n'est pas stocké, c'est la courbe d'un repas** : l'extrait de mesures autour de lui, rééchantillonné, avec son pic et son verdict.
3. Au chargement de l'app, **et** à chaque arrivée de nouvelles mesures HealthKit, l'app recalcule ces courbes — mais **seulement pour les repas de moins de 45 jours**.
4. Le **verdict** et le **ratio effectif** sont, eux, persistés au passage. Ils survivent donc indéfiniment.
Au-delà de 45 jours, un repas garde son verdict, sa dose et son ratio, mais **plus sa courbe**.
### ⚠️ La justification de cette borne a expiré
Le commentaire dans le code dit : _« sans CGM aussi ancien (backfill Dexcom borné à 7 jours), l'analyse serait de toute façon_ `_donneesManquantes_` _»_.

C'était vrai **à l'époque Dexcom** : l'API ne rendait que 7 jours d'historique, donc chercher à analyser un repas de deux mois n'aurait rien donné.

Ça ne l'est plus. Depuis le passage à HealthKit, l'ingestion est **incrémentale et continue** : le premier import remonte 7 jours, puis tout ce qui arrive s'accumule. Le hub gagne donc de l'historique CGM en permanence. Dans six mois il en contiendra six mois, et un repas de trois mois **aura** ses mesures disponibles — mais restera hors de la fenêtre de 45 jours, donc sans courbe.

La seconde moitié de la justification, elle, reste valable : la borne limite aussi le volume de mesures chargé à chaque rafraîchissement. C'est un vrai coût, mais c'est un choix de performance — pas une impossibilité, comme le laisse croire le commentaire actuel.

### Ce que ça change pour la recherche
Une recherche sur plusieurs mois rendra :

- des repas **récents** avec leur courbe ;
- des repas **anciens** avec leur date, leurs aliments, leur dose, leur ratio et leur verdict — mais une colonne courbe vide.
Ça ne justifie pas de borner la recherche : les chiffres d'un repas d'il y a huit mois répondent très bien à « comment j'avais géré ça ». Mais l'écran doit **le dire** — « courbe non conservée » plutôt qu'une case blanche, qui se lirait comme une donnée manquante ou un bug.
**Asymétrie à connaître** : côté sport, la réponse glycémique se recalcule à la demande, sans fenêtre. Les séances anciennes gardent donc leur courbe, les repas anciens non.

### À décider un jour
Élargir ou supprimer la fenêtre des 45 jours pour les repas est **possible sans rien changer au modèle de données** — les mesures sont là. C'est un arbitrage de coût de rafraîchissement, à reprendre quand l'historique aura grossi. Pas un chantier urgent : à trois semaines de saisie réelle, la fenêtre ne coupe rien.

---

## La règle du dénominateur, en clair
Le dernier bloc du schéma dit « assez de résultats ? ». Ce que ça recouvre :

- **Aucun résultat** → on le dit (« aucune séance de tennis enregistrée »). Un écran vide n'est pas une réponse.
- **Moins de 5** → on montre les cas un par un. Une « moyenne » sur deux séances est un chiffre inventé sur deux points.
- **5 ou plus** → on montre la synthèse, et **chaque moyenne est collée au nombre sur lequel elle repose**.
Ce dernier point n'est pas cosmétique. Sur six séances de tennis, si une seule n'a pas de CGM et une seule n'a pas eu de resucrage, la carte affiche : effectif 6, départ moyen sur 5, glucides moyens sur 5. Trois dénominateurs différents dans le même bloc — sans quoi « 26 g en moyenne » se lirait comme vrai des six.
Le seuil de 5 est réglable dans les Réglages.

---

## Ce que la recherche ne fait pas
- Elle ne recommande rien. Elle montre ce qui s'est passé, et pourquoi chaque résultat est là.
- Elle n'invente pas de valeur manquante. Une séance sans couverture CGM est **écartée** d'un critère de glycémie, jamais supposée conforme — et reste comptée au dénominateur.
- Elle ne devine pas ce que l'utilisateur veut dire. « Correction » et « resucrage » sont deux facettes distinctes : l'une est de l'insuline, l'autre des glucides.
