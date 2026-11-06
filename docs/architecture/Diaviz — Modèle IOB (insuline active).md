# Modèle IOB — Insuline active (Insulin On Board)
>   Source de vérité du calcul d'IOB de Diaviz. **Estimation** des patterns d'insuline résiduelle, **jamais** un calcul de dose. Diaviz n'est pas un dispositif médical.  

**Statut** : 🟢 Adopté (2026-06-20) · **Implémentation** : `Diaviz/services/derivation/IOBCalculateur.swift` + `IOBService.swift` 

---

## 1. Définition
L'**IOB** (Insulin On Board) = quantité d'insuline rapide encore active dans le corps à un instant donné, exprimée en unités. C'est une **dérivation** : calculée à la volée depuis les injections rapides du hub, jamais persistée (« un hub, des dérivations »).

Pour `N` injections rapides de dose `dose_i` faites aux instants `t_i` :

```
IOB_total(T) = Σ_i  dose_i · IOB(T − t_i)
```
où `IOB(t)` est la **fraction de dose restante** `t` minutes après une injection unique (modèle ci-dessous).

---

## 2. Modèle exponentiel (adopté)
Modèle de référence des apps modernes (Loop / OpenAPS), dérivé par Dragan Maksimović (dm61). Deux paramètres physiologiques :

- `td`  = **durée d'action totale (DIA)**, en minutes — vient du **profil utilisateur** (`dureeActionInsulineHeures × 60`  ).
- `tp`  = **temps du pic d'activité**, en minutes — **dérivé du type d'insuline** du profil (voir §4).
### Constantes dérivées
```
tau = tp · (1 − tp/td) / (1 − 2·tp/td)
a   = 2·tau / td
S   = 1 / (1 − a + (1 + a)·e^(−td/tau))
```
### Activité insulinique (fraction de dose absorbée par minute)
```
IA(t) = (S / tau²) · t · (1 − t/td) · e^(−t/tau)        pour 0 ≤ t ≤ td
```
### IOB — fraction de dose restante
```
IOB(t) = 1 − S·(1 − a)·[ ( t²/(tau·td·(1−a)) − t/tau − 1 )·e^(−t/tau) + 1 ]   pour 0 ≤ t ≤ td

IOB(t) = 1     pour t < 0      (avant l'injection)
IOB(t) = 0     pour t ≥ td     (insuline consommée)
```
`IOB(t)` est l'intégrale de l'activité restante : `IOB(t) = 1 − ∫₀ᵗ IA(s) ds`.

---

## 3. Garde-fou numérique
Le modèle n'est défini que si `**td > 2·tp**` (sinon `1 − 2·tp/td ≤ 0` et `tau` diverge). On **clampe** `tp ≤ 0.45·td` avant calcul. Exemple : DIA 3 h (180 min) → `tp` plafonné à 81 min, ce qui couvre les pics réels (55–75 min).

---

## 4. Peak time par insuline (paramètre dynamique)
Valeurs issues des profils pharmacocinétiques publiés (analogues vs ultra-rapides). Table appliquée à `ProfilUtilisateur.insulineRapide` :

| Insuline | Type | `tp` (min) |
| ----- | ----- | ----- |
| Novorapid (aspart) | analogue rapide | 75 |
| Humalog (lispro) | analogue rapide | 75 |
| Apidra (glulisine) | analogue rapide | 75 |
| Fiasp (faster aspart) | ultra-rapide | 55 |
| Lyumjev (faster lispro) | ultra-rapide | 55 |
| Autre | défaut prudent | 75 |
| `td` (DIA) reste indépendant et configurable dans le profil (3–6 h). **Tout est dynamique** : aucune constante figée dans le calcul, les deux paramètres viennent du profil. |  |  |
---

## 5. Sources
- **LoopKit** — `ExponentialInsulinModel`  : github.com/LoopKit/LoopKit (implémentation de référence).
- **OpenAPS docs** — « Insulin curves » / modèle exponentiel.
- **Dragan Maksimović (dm61)** — dérivation des « Exponential Insulin Activity Curves » (communauté Loop/OpenAPS).
---

## 6. Implémentation Diaviz
- `IOBCalculateur`  (`services/derivation/`  ) — formule pure, `Sendable`  , `nonisolated`  (réutilisable hors `MainActor`  , ex. ML). Expose `iob(a:injections:diaHeures:picMinutes:)`  et `courbe(...)`  .
- `InsulineRapide.picActionMinutes`  — table du §4.
- `IOBService`  (`@Observable @MainActor`  ) — lit les injections rapides du hub (fenêtre DIA), applique le modèle avec `td`  (profil) et `tp`  (type d'insuline). Expose `iobCourant`  + `courbe`  (décroissance 6 h).
- **Branchements** : carte « Insuline active » de l'accueil (IOB réel) ; `iobAuDebut`  figé à la saisie d'un repas / d'une activité via `IOBService.iobDuHub(a:contexte:)`  .
- **V1** : recalcul à l'apparition de l'accueil (`.onAppear`  ), pas de timer temps réel (l'IOB affiché est figé entre deux apparitions). Rafraîchissement continu (`TimelineView`  ) = amélioration future si besoin.
---

## 7. Ancien modèle (déprécié)
Avant le 2026-06-20, l'IOB utilisait un modèle **bicubique Hermite** (deux cubiques `smoothstep` raccordées au pic, répartition 40 %/60 % arbitraire). Lisse mais **non fondé sur la pharmacocinétique** — remplacé par le modèle exponentiel ci-dessus. Subsiste uniquement dans `AccueilMetriquesServiceMock` pour les previews, à nettoyer quand les autres cartes d'accueil passeront au réel.
