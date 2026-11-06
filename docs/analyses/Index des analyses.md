# Index des analyses
>   Vue d'ensemble de toutes les analyses Diaviz. Chaque analyse a son propre fichier dans ce dossier. 

⚠️ **Contrainte dominante : le volume de données.** Les analyses non commencées supposent un historique de plusieurs mois. Ce n'est pas de la dette technique, c'est une roadmap en attente de données.

---

## Analyses actives
| ID | Nom | Type | Statut | Priorité |
| ----- | ----- | ----- | ----- | ----- |
| B1 | Détection basale inadaptée | Stat. descriptive | 🟢 Implémenté (V1, on-device) | ⭐⭐⭐⭐⭐ |
| B2 | Endormissement + corrections (fusionné avec B3) | Stat. descriptive (situations minées par énumération) | 🟢 Implémenté (page « Hypos au coucher ») | ⭐⭐⭐⭐ |
| B3 | Corrections du soir | Stat. descriptive (Random Forest abandonné) | 🟢 Implémenté (fusionné dans B2) | ⭐⭐⭐⭐ |
| R1 | Corrélation repas/insuline | Stat. descriptive (pas de CreateML/Random Forest) | 🟢 Implémenté (socle + mining + insights accueil) | ⭐⭐⭐⭐⭐ |
| S1 | Réponse glycémique sport | Stat. descriptive (pas de ML) | <p>🟡 Partiel — réponse par séance livrée, </p><p>**mining agrégé**</p><p> en attente de volume</p> | ⭐⭐⭐⭐ |
| C1 | Épisodes de charge (page « Charge et glycémie ») | Stat. descriptive (pas de ML) | 🟢 V1 livrée le 2026-10-18 — horizon limité à 90 jours | ⭐⭐⭐⭐ |
| R2 | Ratio sport actif au repas | Stat. descriptive attendue | 🔴 Non commencé — attend R1 + S1 agrégé | ⭐⭐⭐ |
| E1 | Corrélation état/glycémie | Stat. descriptive attendue | 🔴 Non commencé — **bloqué en amont** : `EtatDeclare` existe, aucune UI de saisie | ⭐⭐⭐ |
| M1 | Impact médicaments | Stat. descriptive attendue | 🔴 Non commencé — **bloqué en amont** : `Medicament` existe, aucune UI de saisie | ⭐⭐ |
| S2 | Glucides pré-sport | Stat. descriptive attendue | 🔴 Non commencé — attend S1 agrégé | ⭐⭐ |
| R3 | Repas custom sans glucides | Stat. descriptive attendue | 🔴 Non commencé (débloqué par R1) | ⭐⭐ |
| RB1 | Ratio de base optimal | Stat. descriptive attendue | 🔴 Non commencé | ⭐ |
La colonne **Type** disait « ML » pour toutes les analyses non commencées. C'est un reste du cadrage initial : le repo ne contient **ni CreateML ni CoreML**, et chaque analyse cadrée « ML » a finalement été livrée en statistique descriptive. Précédent réglementaire acté — un modèle opaque est trop proche du conseil. Partir du principe que la prochaine analyse sera descriptive elle aussi, et ne réintroduire du ML que sur un besoin démontré.

>   Voir le détail dans les fichiers dédiés : **B1 — Détection basale**, **B2 — Endormissement (hypos au coucher)** (contient la fusion B2+B3), **R1 — Réponse glycémique post-repas**, **S1 — Réponse glycémique sport**, **C1 — Frise des périodes** (épisodes de charge), **Cartes d'insights accueil — Nouvelles tendances**. Une **Bibliothèque** existe désormais dans l'app (Profil → Bibliothèque) et recense les synthèses sourcées de la littérature qui ont informé le cadrage des analyses. 

---

## Ordre de dev recommandé
B1 → B2 → B3 → R1 → S1 → R2 → E1 → M1 → S2 → R3 → RB1

**Fait** : B1, B2, B3, R1, C1 (V1). **Partiel** : S1.

**S1** est terminé côté verdicts par séance ; son mining agrégé (lot 4b) attend d'avoir assez de séances enregistrées.

**Candidats suivants** — tous conditionnés au volume de données, aucun lançable aujourd'hui :

- **S1 agrégé** — mining entre séances ; débloque S2 et R2.
- **R2** — ratio sport au repas, débloqué par R1 + S1 agrégé.
- **Croisement sport / nuit** — identifié pendant le cadrage S1 : l'hypoglycémie retardée survient 7 à 24 h après l'effort et recoupe directement B1/B2. Piste jugée la plus prometteuse, mais la plus gourmande en historique.
- **E1 / M1** — exigent d'abord un **écran de saisie** (état déclaré, médicaments). Les modèles existent dans le schéma, rien ne les alimente. Chantier de saisie avant chantier d'analyse.
---

## Template pour nouvelles analyses
Chaque doc d'analyse suit cette structure :

```
# [ID] — [Nom]
> TL;DR en 2-3 lignes.
Statut · Type · Priorité

## Pourquoi
Le problème résolu (3 bullets max)

## Quoi
Ce que l'analyse produit concrètement (verdicts, métriques, insights)

## Comment
Méthode, données, seuils, UI, évolution
```
