// Animations au défilement. Si le système demande moins d'animations,
// ou si GSAP n'est pas chargé, la page reste entière et immobile.
// Étapes d'une notion : un toucher sur une ligne change l'écran ; sur grand
// écran, le défilement les fait aussi avancer (notion épinglée).
const etapesNotions = [...document.querySelectorAll('.notion-etapes')].map((notion) => {
  const img = notion.querySelector('.ecran img');
  const boutons = [...notion.querySelectorAll('.etapes button')];
  const doux = !window.matchMedia('(prefers-reduced-motion: reduce)').matches && window.gsap;
  let courant = 0;
  const montrer = (i) => {
    if (i === courant) return;
    courant = i;
    const b = boutons[i];
    boutons.forEach((x, k) => x.setAttribute('aria-current', String(k === i)));
    const changer = () => { img.src = b.dataset.src; img.alt = b.dataset.alt; };
    if (!doux) return changer();
    gsap.killTweensOf(img);
    gsap.to(img, { opacity: 0, duration: .15, onComplete: () => {
      changer();
      gsap.to(img, { opacity: 1, duration: .3 });
    } });
  };
  boutons.forEach((b, i) => b.addEventListener('click', () => {
    montrer(i);
    // En une colonne, l'écran est au-dessus du texte : on le ramène à la vue.
    if (window.matchMedia('(max-width: 960px)').matches) {
      notion.querySelector('.iphone').scrollIntoView({ behavior: doux ? 'smooth' : 'auto', block: 'center' });
    }
  }));
  // Précharge les écrans suivants.
  boutons.slice(1).forEach((b) => { const i = new Image(); i.src = b.dataset.src; });
  return { notion, boutons, montrer };
});

(() => {
  const reduire = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  if (reduire || !window.gsap || !window.ScrollTrigger) return;

  gsap.registerPlugin(ScrollTrigger);
  gsap.defaults({ ease: 'power3.out' });

  // En-tête : apparition en cascade, iPhone qui monte.
  gsap.from('.entete-texte > *', { y: 24, opacity: 0, duration: .8, stagger: .07 });
  gsap.from('.entete-iphone .iphone', { y: 80, opacity: 0, rotate: 4, duration: 1.1, delay: .2 });

  // Titres et textes de section.
  gsap.utils.toArray('.section .surtitre, .section h2, .section .intro').forEach((el) => {
    gsap.from(el, { y: 28, opacity: 0, duration: .8, scrollTrigger: { trigger: el, start: 'top 88%' } });
  });

  // Pourquoi : les tuiles arrivent en désordre, puis se rangent.
  gsap.from('.tuile', {
    y: 50, opacity: 0, rotate: () => gsap.utils.random(-6, 6), duration: .9, stagger: .08,
    scrollTrigger: { trigger: '.tuiles', start: 'top 82%' },
  });

  // Quoi : les sources convergent vers le journal (scène épinglée).
  const visuel = document.querySelector('.scene-visuel');
  const puces = gsap.utils.toArray('.puce');
  const lignes = gsap.utils.toArray('.journal li');
  const ecart = () => {
    const l = visuel.clientWidth, h = visuel.clientHeight;
    return { dx: Math.min(l * .42, 230), dy: h * .42 };
  };
  gsap.set(puces, {
    xPercent: -50, yPercent: -50, opacity: 1,
    x: (i, el) => ecart().dx * +el.dataset.x,
    y: (i, el) => ecart().dy * +el.dataset.y,
  });
  gsap.set('.journal', { scale: .55, opacity: 0 });
  gsap.set(lignes, { opacity: 0, x: -12 });

  const etroit = window.matchMedia('(max-width: 960px)').matches;
  const tl = gsap.timeline({
    scrollTrigger: {
      trigger: etroit ? '.scene-visuel' : '.scene',
      start: etroit ? 'top 70%' : 'top top',
      end: etroit ? 'bottom 40%' : '+=900',
      scrub: .6,
      pin: !etroit,
      invalidateOnRefresh: true,
    },
  });
  tl.to(puces, { x: 0, y: 0, scale: .5, opacity: 0, duration: 1, stagger: .05, ease: 'power2.in' })
    .to('.journal', { scale: 1, opacity: 1, duration: .6, ease: 'back.out(1.4)' }, '-=.45')
    .to(lignes, { opacity: 1, x: 0, duration: .4, stagger: .08 }, '-=.2');

  // Comment : cartes en cascade.
  gsap.from('.regle', {
    y: 40, opacity: 0, duration: .8, stagger: .12,
    scrollTrigger: { trigger: '.regles', start: 'top 85%' },
  });

  // Notions : l'iPhone glisse légèrement pendant le défilement, le texte apparaît.
  gsap.utils.toArray('.notion').forEach((n) => {
    gsap.from(n.querySelector('.notion-texte'), {
      y: 36, opacity: 0, duration: .8, scrollTrigger: { trigger: n, start: 'top 80%' },
    });
    // Léger glissement de l'écran, sur grand écran seulement : en une
    // colonne, il le ferait chevaucher le texte.
    if (window.matchMedia('(min-width: 961px)').matches) {
      gsap.fromTo(n.querySelector('.iphone'), { y: 60 }, {
        y: -40, ease: 'none', scrollTrigger: { trigger: n, start: 'top bottom', end: 'bottom top', scrub: true },
      });
    }
  });

  // Étapes : sur grand écran, la notion reste à l'écran pendant que le
  // défilement fait passer d'un écran à l'autre.
  if (window.matchMedia('(min-width: 961px)').matches) {
    etapesNotions.forEach(({ notion, boutons, montrer }) => {
      ScrollTrigger.create({
        trigger: notion, start: 'center center', end: `+=${(boutons.length - 1) * 420}`,
        pin: true, onUpdate: (st) => montrer(Math.min(boutons.length - 1, Math.floor(st.progress * boutons.length))),
      });
    });
    // Épingles créées après les autres déclencheurs : remise dans l'ordre
    // de la page pour que les positions suivantes tiennent compte de la pause.
    ScrollTrigger.sort();
    ScrollTrigger.refresh();
  }

  // Limites : une ligne après l'autre.
  gsap.from('.non li', {
    x: -24, opacity: 0, duration: .6, stagger: .08,
    scrollTrigger: { trigger: '.non', start: 'top 85%' },
  });
})();
