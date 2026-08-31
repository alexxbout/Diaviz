//
//  Grain.metal
//  diaviz
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>

using namespace metal;

/// Grain de film appliqué pixel par pixel sur la couleur déjà rendue.
///
/// Le bruit est **calculé**, jamais échantillonné dans une texture : rien à
/// embarquer dans le bundle, aucun motif qui se répète (l'œil finit par voir
/// la trame d'une tuile sur une grande surface), et la densité reste la même
/// quelle que soit la taille de la carte.
///
/// Le hash sinus/fract est l'astuce classique du bruit pseudo-aléatoire en
/// shader : déterministe pour une position donnée, donc stable d'une frame à
/// l'autre — un grain qui scintillerait à chaque re-rendu serait
/// insupportable sous du texte.
///
/// - Parameters:
///   - position: coordonnée du pixel, en points de la vue.
///   - couleur: couleur déjà rendue à cette position.
///   - intensite: amplitude du bruit (0 = aucun).
///   - graine: décorrèle deux surfaces voisines, qui partageraient sinon
///     exactement le même motif.
[[ stitchable ]] half4 grainDiaviz(float2 position, half4 couleur, float intensite, float graine) {
    float2 point = position + graine;
    float aleatoire = fract(sin(dot(point, float2(12.9898, 78.233))) * 43758.5453);

    // Bruit centré sur zéro : il éclaircit autant qu'il assombrit, la
    // luminosité moyenne du dégradé reste donc celle qui a été choisie.
    half ecart = half(aleatoire - 0.5) * half(intensite);

    // Multiplié par l'alpha : sur une zone transparente, le grain ne doit pas
    // faire apparaître de matière là où il n'y a rien.
    return half4(couleur.rgb + ecart * couleur.a, couleur.a);
}
