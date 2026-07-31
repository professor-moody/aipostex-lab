---
title: See you at DEF CON!
hide:
  - navigation
  - toc
  - footer
---

<style>
  /* Hold the lab back until con day: this page is a clean splash — no nav tabs,
     no sidebars, no repo/search chrome tempting a click into the lab content. */
  .md-tabs, .md-sidebar, .md-search, .md-header__source { display: none !important; }
  .md-main__inner { margin-top: 0; }
  .dc-hero {
    min-height: 78vh;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    text-align: center;
    padding: 2rem 1rem;
  }
  .dc-hero h1 {
    font-size: clamp(2.6rem, 10vw, 6.5rem);
    font-weight: 800;
    line-height: 1.05;
    margin: 0;
    background: linear-gradient(90deg,
      #a855f7, #8b5cf6, #6366f1, #3b82f6, #06b6d4, #3b82f6, #6366f1, #8b5cf6, #a855f7);
    background-size: 300% auto;
    -webkit-background-clip: text;
    background-clip: text;
    color: transparent;
    -webkit-text-fill-color: transparent;
    animation: dc-shimmer 7s linear infinite;
  }
  @keyframes dc-shimmer { to { background-position: 300% center; } }
  .dc-hero .dc-sub {
    margin-top: 1.6rem;
    font-size: clamp(.85rem, 2.4vw, 1.1rem);
    letter-spacing: .28em;
    text-transform: uppercase;
    color: #7b7b8b;
    font-weight: 600;
  }
  @media (prefers-reduced-motion: reduce) {
    .dc-hero h1 { animation: none; background-position: 50% center; }
  }
</style>

<div class="dc-hero" markdown="0">
  <h1>See you at DEF&nbsp;CON!</h1>
  <div class="dc-sub">Red Team Village &middot; DEF CON 34</div>
</div>
