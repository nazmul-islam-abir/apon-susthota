<?php
/**
 * AponSusthota — Patient-First Landing Page
 *
 * This is phase 1 of the landing page (PATIENT ONLY).
 * Follows the layout philosophy of `landingpagehelper/index.php`
 * (sticky glass nav, hero with phone mockup + floating pills,
 * scroll-snap screenshot row, three-card subscription portal,
 * mandatory charge disclosure) but restyled for AponSusthota's
 * sage palette (#305D51 → #558E7D) and rewritten around the
 * patient's everyday health journey.
 *
 * The BDApps integration reuses the proven endpoints:
 *   - send_otp.php        (subscribe step 1 — sends OTP)
 *   - verify_otp.php      (subscribe step 2 — confirms subscription)
 *   - check_subscription.php (status check)
 *   - unsubscribe.php     (unsubscribe request)
 *
 * Caretaker, emotional-connection, "one-app" diagram, and the
 * final "Be There Even When You Can't Be There" CTA are reserved
 * for the next phase — section anchors are already in the nav so
 * the page can grow without rewriting this file.
 */

$APP_ID           = 'NADB26045';
$APP_ID_INTERNAL  = 'APP_140036';
$APP_NAME         = 'আপন সুস্থতা';
$APP_NAME_EN      = 'AponSusthota';
$TAGLINE          = 'Connected care for the people you love';
$TAGLINE_BN       = 'প্রিয়জনের স্বাস্থ্য, এখন সবসময় আপনার সাথে';

$APP_CATEGORY     = 'Health & Fitness';

// APK URL — same pattern as the reference: lives on the cPanel
// account under the BDApps folder. Adjust once you publish.
$APK_DOWNLOAD_URL = 'https://aponshusthota.byabir.com/apk/apon_susthota.apk';

$UNSUBSCRIBE_URL  = 'https://bdappsdigitalapps.com/subscription/manage?app=' . $APP_ID;

$SUPPORT_EMAIL    = 'support@bdapps.com';
$SUPPORT_PHONE    = '+8809610999922';
$PRIVACY_URL      = '#privacy';
$FAQ_URL          = '#faq';

// Pricing — keep these in lockstep with the in-app Subscription
// screen and the BDApps FAQ.
$PRICE_DAILY_BDT    = '2.78';
$PRICE_BUNDLED_BDT  = '5.56';
$PRICE_MONTHLY_BDT  = '299';
$PRICE_YEARLY_BDT   = '199';
$PRICE_OPERATOR     = 'Robi and Cirkle';

$CHARGE_DISCLAIMER  = 'Subscribe now for ৳' . $PRICE_DAILY_BDT
                    . ' / day (incl. Vat+SC+SD) on ' . $PRICE_OPERATOR
                    . ' and unlock the full ' . $APP_NAME . ' experience.';

$PLATFORMS = ['Android'];
?>
<!DOCTYPE html>
<html lang="bn">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <meta name="theme-color" content="#305D51" />
  <title><?php echo htmlspecialchars($APP_NAME); ?> — <?php echo htmlspecialchars($TAGLINE); ?></title>
  <meta name="description" content="<?php echo htmlspecialchars($APP_NAME); ?> helps patients manage everyday health — meals, workout, water, mood, medicine — and keeps loved ones connected through a 6-digit caretaker code." />

  <link rel="preconnect" href="https://fonts.googleapis.com" />
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
  <link href="https://fonts.googleapis.com/css2?family=Roboto:wght@400;500;600;700;800&display=swap" rel="stylesheet" />

  <link rel="stylesheet" href="assets/css/style.css?v=20260911" />
  <link rel="icon" type="image/png" href="images/logo.png" />
</head>
<body>

  <!-- ===== Navigation ===== -->
  <nav class="nav">
    <div class="nav-inner">
      <a href="#top" class="brand">
        <span class="brand-logo" aria-hidden="true">
          <img src="images/logo.png" alt="" />
        </span>
        <span><?php echo htmlspecialchars($APP_NAME); ?></span>
      </a>
      <ul class="nav-links">
        <li><a href="#story">Story</a></li>
        <li><a href="#features">Features</a></li>
        <li><a href="#screens">Screens</a></li>
        <li><a href="#daily">Daily life</a></li>
        <li><a href="#report">30-day report</a></li>
        <li><a href="#caretaker">Caretaker</a></li>
        <li><a href="#voice">Voice</a></li>
        <li><a href="#subscribe">Subscribe</a></li>
      </ul>
      <a href="#subscribe" class="nav-cta">Subscribe</a>
    </div>
  </nav>

  <!-- ===== Hero ===== -->
  <header id="top" class="hero">
    <div class="container">
      <div class="hero-grid">
        <div class="hero-text">
          <span class="hero-eyebrow">
            <span class="dot"></span>
            Now available for <?php echo htmlspecialchars($PRICE_OPERATOR); ?>
          </span>
          <h1>
            Take control of<br />
            your <span class="accent">everyday health.</span>
          </h1>
          <p class="lead">
            <?php echo htmlspecialchars($APP_NAME); ?> is a Bangla-first health companion built around
            the meals you actually eat, the medicines you take, and the small daily habits that decide
            how you feel in 30 days.
          </p>

          <div class="hero-cta">
            <a href="#subscribe" class="btn btn-primary">
              Subscribe now
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14M13 6l6 6-6 6"/></svg>
            </a>
            <a href="<?php echo htmlspecialchars($APK_DOWNLOAD_URL); ?>" class="btn btn-ghost">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4M7 10l5 5 5-5M12 15V3"/></svg>
              Download APK
            </a>
          </div>

          <div class="hero-meta">
            <div class="hero-meta-item">
              <span class="icon">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><rect x="5" y="2" width="14" height="20" rx="2"/><path d="M12 18h.01"/></svg>
              </span>
              Android only
            </div>
            <div class="hero-meta-item">
              <span class="icon">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2 4 6v6c0 5 3.5 9.5 8 10 4.5-.5 8-5 8-10V6l-8-4z"/></svg>
              </span>
              Secure BDApps OTP login
            </div>
            <div class="hero-meta-item">
              <span class="icon">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg>
              </span>
              Cancel anytime
            </div>
          </div>
        </div>

        <div class="hero-visual">
          <div class="hero-floating hero-floating-1">
            <div class="icon-bubble green">
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2 4 6v6c0 5 3.5 9.5 8 10 4.5-.5 8-5 8-10V6l-8-4z"/></svg>
            </div>
            <div>
              <div class="title">Today's water</div>
              <div class="value">0.50 / 2.5 L</div>
            </div>
          </div>

          <div class="hero-floating hero-floating-2">
            <div class="icon-bubble coral">
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18M3 12h18M3 18h18"/></svg>
            </div>
            <div>
              <div class="title">Daily plan</div>
              <div class="value">4 / 10 meals</div>
            </div>
          </div>

          <div class="phone">
            <!-- Top hero mainimage: the actual patient home screen from
                 the live build (see checkmyss/apps/...). Replaces the
                 earlier mock dashboard so prospects see the real UI. -->
            <img src="images/app-mainimage.png" alt="<?php echo htmlspecialchars($APP_NAME); ?> dashboard preview" />
          </div>
        </div>
      </div>
    </div>
  </header>

  <!-- ===== Stats strip ===== -->
  <section class="section" style="padding-top: 0;">
    <div class="container">
      <div class="stats">
        <div class="stat-card">
          <div class="num">30-Day</div>
          <div class="label">Meal plan</div>
        </div>
        <div class="stat-card">
          <div class="num">Daily</div>
          <div class="label">Tracking</div>
        </div>
        <div class="stat-card">
          <div class="num">AI</div>
          <div class="label">Assistant</div>
        </div>
        <div class="stat-card">
          <div class="num">PDF</div>
          <div class="label">Doctor report</div>
        </div>
      </div>
    </div>
  </section>

  <!-- ===== Story / description — three brand pillars (1.png/2.png/3.png) ===== -->
  <section id="story" class="section" style="background: rgba(255,255,255,0.4);">
    <div class="container">
      <div class="section-head">
        <span class="section-eyebrow">Why this app</span>
        <h2>One app for health, care, and connection</h2>
        <p class="sub">
          Built for the moments that matter most — managing your day, caring for someone you love,
          and staying close even when you can't be in the same room.
        </p>
      </div>

      <div class="hscroll fade-up" style="padding-left: 4px;">
        <div class="hscroll-img-card">
          <div class="frame">
            <span class="badge">তোমার দৈনিক স্বাস্থ্য</span>
            <img src="images/1.png" alt="Everyday health — meals, workout, water, mood, medicine" loading="lazy" />
          </div>
          <div class="body">
            <h3>তোমার দৈনিক স্বাস্থ্য</h3>
            <p>
              প্রতিদিনের খাবার, ব্যায়াম, পানি, ওষুধ এবং মেজাজ — একটি শান্ত বাংলা ইন্টারফেসে।
              ৩০ দিনের পরিকল্পনা, ব্যক্তিগত সুপারিশ, এবং ডাক্তারের জন্য একটি পরিষ্কার রিপোর্ট।
            </p>
          </div>
        </div>

        <div class="hscroll-img-card">
          <div class="frame">
            <span class="badge">বন্ধন — যারা তোমাকে ভালোবাসে</span>
            <img src="images/2.png" alt="Caregiver connection — keep loved ones close" loading="lazy" />
          </div>
          <div class="body">
            <h3>পরিবারের সাথে বন্ধন</h3>
            <p>
              ৬ অক্ষরের কোড শেয়ার করো, প্রিয়জন তোমাকে সংযুক্ত করুক। তাদের দৈনিক অগ্রগতি
              সরাসরি দেখো — সব আপডেট realtime-এ, কোনো ফোন কল ছাড়াই।
            </p>
          </div>
        </div>

        <div class="hscroll-img-card">
          <div class="frame">
            <span class="badge">ভয়েসে পাঠাও, ভয়েসে রইলো</span>
            <img src="images/3.png" alt="Voice messages — record, schedule, listen" loading="lazy" />
          </div>
          <div class="body">
            <h3>ভয়েসে একটু যত্ন</h3>
            <p>
              টাইপ করার দরকার নেই। মাইকে চেপে একটু ভালোবাসা পাঠাও — সময় ঠিক করে দাও, ঠিকানায়
              পৌঁছে যাবে। রোগী চাইলে ভয়েসে উত্তরও দিতে পারে।
            </p>
          </div>
        </div>
      </div>

      <!-- Soft inline hint that the row scrolls. -->
      <p style="text-align: center; font-size: 12.5px; color: var(--text-hint); margin-top: -8px;">
        ← বামে-ডানে স্ক্রল করুন →
      </p>
    </div>
  </section>

  <!-- ===== Patient features ===== -->
  <section id="features" class="section">
    <div class="container">
      <div class="section-head">
        <span class="section-eyebrow">Features</span>
        <h2>Everything you need to stay on track</h2>
        <p class="sub">
          Built around the meals you actually eat, the medicines you take, and the small habits that decide
          how you feel in 30 days.
        </p>
      </div>

      <!-- Horizontal scroll row of patient features. Each card is
           fixed-width (280px) so it never wraps, keeping the page
           compact and letting visitors flick through every feature. -->
      <div class="hscroll fade-up">
        <div class="hscroll-feature">
          <div class="feature-icon">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.29 1.51 4.04 3 5.5l7 7Z"/></svg>
          </div>
          <h3>Personal health tracking</h3>
          <p>Record blood pressure, blood glucose (fasting + post-meal), HbA1c and insulin use. A clearer picture of your health progress, day by day.</p>
        </div>

        <div class="hscroll-feature amber">
          <div class="feature-icon">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18M3 12h18M3 18h18"/></svg>
          </div>
          <h3>30-day personalized meal plan</h3>
          <p>Generated from your profile and health info. View, modify, swap with AI — and see exactly how well you followed the plan.</p>
        </div>

        <div class="hscroll-feature coral">
          <div class="feature-icon">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M6.5 6.5 17.5 17.5"/><path d="m21 21-1-1"/><path d="m3 3 1 1"/><path d="M18 22 4 8l3-3 14 14Z"/></svg>
          </div>
          <h3>Personalized workout roadmap</h3>
          <p>Daily exercises with built-in timer, video guidance and an analysis page — track what you completed and what to improve next.</p>
        </div>

        <div class="hscroll-feature">
          <div class="feature-icon">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2.69 5 7v6c0 5 3 9 7 11 4-2 7-6 7-11V7l-7-4.31Z"/></svg>
          </div>
          <h3>Daily water tracking</h3>
          <p>Tap to log a glass, a cup, or a sip. See your daily progress, history and weekly trend — without forgetting.</p>
        </div>

        <div class="hscroll-feature amber">
          <div class="feature-icon">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M8 14s1.5 2 4 2 4-2 4-2"/><path d="M9 9h.01M15 9h.01"/></svg>
          </div>
          <h3>Mood tracking</h3>
          <p>Because everyday health is mental health too. Log how you feel each day and see the patterns behind your better weeks.</p>
        </div>

        <div class="hscroll-feature coral">
          <div class="feature-icon">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="m10.5 20.5 10-10a4.95 4.95 0 1 0-7-7l-10 10a4.95 4.95 0 0 0 7 7Z"/><path d="m8.5 8.5 7 7"/></svg>
          </div>
          <h3>Medicine management</h3>
          <p>Add medicines with schedule and dosage, get reminders, and never lose track of an important dose. Let the AI help fill in details.</p>
        </div>

        <div class="hscroll-feature">
          <div class="feature-icon">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2v4M12 18v4M4.93 4.93l2.83 2.83M16.24 16.24l2.83 2.83M2 12h4M18 12h4M4.93 19.07l2.83-2.83M16.24 7.76l2.83-2.83"/></svg>
          </div>
          <h3>AI health assistant</h3>
          <p>Ask about your data, request meal ideas, or get help adding medicines. Guidance, not a diagnosis — your doctor still decides.</p>
        </div>

        <div class="hscroll-feature amber">
          <div class="feature-icon">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6"/><path d="M16 13H8M16 17H8M10 9H8"/></svg>
          </div>
          <h3>30-day doctor report</h3>
          <p>Turn 30 days of daily habits into one clear PDF — show your doctor exactly how you've been maintaining your routine.</p>
        </div>

        <div class="hscroll-feature coral">
          <div class="feature-icon">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.13 1.05.37 2.07.72 3.06a2 2 0 0 1-.45 2.11L8.09 10.91a16 16 0 0 0 6 6l2.02-2.02a2 2 0 0 1 2.11-.45c.99.35 2.01.59 3.06.72A2 2 0 0 1 22 16.92z"/></svg>
          </div>
          <h3>Emergency assistance</h3>
          <p>Find the nearest hospital with one tap — see distance, address and call directly. Help when it matters most.</p>
        </div>
      </div>

      <p style="text-align: center; font-size: 12.5px; color: var(--text-hint); margin-top: -8px;">
        ← বামে-ডানে স্ক্রল করুন →
      </p>
    </div>
  </section>

  <!-- ===== Screenshots gallery ===== -->
  <section id="screens" class="section" style="background: rgba(255,255,255,0.4);">
    <div class="container">
      <div class="section-head">
        <span class="section-eyebrow">Screens</span>
        <h2>Take a peek inside</h2>
        <p class="sub">A calm, Bangla-first interface that feels at home on any Android device.</p>
      </div>

      <div class="shots-row">
        <div class="shot"><img src="images/patient-onboarding-glucose.png" alt="Health profile onboarding" /></div>
        <div class="shot"><img src="images/patient-dashboard.png" alt="Daily dashboard" /></div>
        <div class="shot"><img src="images/patient-meal-plan.png" alt="Meal plan" /></div>
        <div class="shot"><img src="images/patient-meal-calendar.png" alt="Meal calendar" /></div>
        <div class="shot"><img src="images/patient-workout-list.png" alt="Workout list" /></div>
        <div class="shot"><img src="images/patient-workout-progress.png" alt="Workout progress" /></div>
        <div class="shot"><img src="images/patient-workout-video.png" alt="Workout video player" /></div>
        <div class="shot"><img src="images/patient-water-tracking.png" alt="Water tracking" /></div>
        <div class="shot"><img src="images/patient-water-analytics.png" alt="Water analytics" /></div>
        <div class="shot"><img src="images/patient-medicine.png" alt="Medicine reminder" /></div>
        <div class="shot"><img src="images/patient-ai-assistant.png" alt="AI assistant" /></div>
        <div class="shot"><img src="images/patient-health-report.png" alt="Health analytics" /></div>
        <div class="shot"><img src="images/patient-daily-report.png" alt="Daily report" /></div>
        <div class="shot"><img src="images/patient-emergency.png" alt="Emergency SOS" /></div>
      </div>
    </div>
  </section>

  <!-- ===== Daily progress mockup — the 4-ring patient dashboard ===== -->
  <section id="daily" class="section">
    <div class="container">
      <div class="section-head">
        <span class="section-eyebrow">Daily life</span>
        <h2>Your day at a glance</h2>
        <p class="sub">
          One calm screen that shows meals, workout, water and medicine as four rings — so you always
          know what's done and what's next.
        </p>
      </div>

      <div class="daily-progress">
        <div class="daily-progress-grid">
          <div class="dp-cell">
            <div class="dp-ring">
              <svg width="64" height="64" viewBox="0 0 64 64">
                <circle cx="32" cy="32" r="26" fill="none" stroke="#FCE9C7" stroke-width="8"/>
                <circle cx="32" cy="32" r="26" fill="none" stroke="#F59E0B" stroke-width="8"
                  stroke-dasharray="163.36" stroke-dashoffset="32.67" stroke-linecap="round"/>
              </svg>
              <div class="label">80%</div>
            </div>
            <div class="dp-info">
              <div class="name">খাবার (Meals)</div>
              <div class="meta">8 / 10 আইটেম</div>
            </div>
          </div>

          <div class="dp-cell">
            <div class="dp-ring">
              <svg width="64" height="64" viewBox="0 0 64 64">
                <circle cx="32" cy="32" r="26" fill="none" stroke="#D6F0DE" stroke-width="8"/>
                <circle cx="32" cy="32" r="26" fill="none" stroke="#558E7D" stroke-width="8"
                  stroke-dasharray="163.36" stroke-dashoffset="130.69" stroke-linecap="round"/>
              </svg>
              <div class="label">20%</div>
            </div>
            <div class="dp-info">
              <div class="name">ব্যায়াম (Workout)</div>
              <div class="meta">2 / 30 মিনিট</div>
            </div>
          </div>

          <div class="dp-cell">
            <div class="dp-ring">
              <svg width="64" height="64" viewBox="0 0 64 64">
                <circle cx="32" cy="32" r="26" fill="none" stroke="#D6E9F7" stroke-width="8"/>
                <circle cx="32" cy="32" r="26" fill="none" stroke="#3B82F6" stroke-width="8"
                  stroke-dasharray="163.36" stroke-dashoffset="81.68" stroke-linecap="round"/>
              </svg>
              <div class="label">50%</div>
            </div>
            <div class="dp-info">
              <div class="name">পানি (Water)</div>
              <div class="meta">10 / 10 গ্লাস</div>
            </div>
          </div>

          <div class="dp-cell">
            <div class="dp-ring">
              <svg width="64" height="64" viewBox="0 0 64 64">
                <circle cx="32" cy="32" r="26" fill="none" stroke="#D6E9F7" stroke-width="8"/>
                <circle cx="32" cy="32" r="26" fill="none" stroke="#3B82F6" stroke-width="8"
                  stroke-dasharray="163.36" stroke-dashoffset="0" stroke-linecap="round"/>
              </svg>
              <div class="label">100%</div>
            </div>
            <div class="dp-info">
              <div class="name">ওষুধ (Medicine)</div>
              <div class="meta">2 / 2 ডোজ</div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </section>

  <!-- ===== How it works — patient journey ===== -->
  <section id="how" class="section" style="background: rgba(255,255,255,0.4);">
    <div class="container">
      <div class="section-head">
        <span class="section-eyebrow">How it works</span>
        <h2>Start in 4 simple steps</h2>
      </div>

      <div class="steps">
        <div class="step">
          <div class="step-num">1</div>
          <h3>Subscribe</h3>
          <p>Confirm via BDApps on your Robi / Cirkle number. Charges appear as ৳<?php echo htmlspecialchars($PRICE_DAILY_BDT); ?> / day.</p>
        </div>
        <div class="step">
          <div class="step-num">2</div>
          <h3>Set up your profile</h3>
          <p>Tell the app about your age, weight and key health numbers — so every plan is built for you.</p>
        </div>
        <div class="step">
          <div class="step-num">3</div>
          <h3>Get your plan</h3>
          <p>Receive a personalized 30-day meal roadmap and workout roadmap, tuned to your health profile.</p>
        </div>
        <div class="step">
          <div class="step-num">4</div>
          <h3>Track daily</h3>
          <p>Log meals, workout, water, mood and medicine. At day 30, download a PDF report for your doctor.</p>
        </div>
      </div>
    </div>
  </section>

  <!-- ===== 30-day report teaser ===== -->
  <section id="report" class="section">
    <div class="container">
      <div class="section-head">
        <span class="section-eyebrow">30-day report</span>
        <h2>Turn 30 days into one clear story</h2>
        <p class="sub">
          After a month of daily logging, AponSusthota generates a downloadable PDF that summarizes meals,
          workout, water, mood, medicine and overall health progress — ready to share with your doctor.
        </p>
      </div>
      <div style="text-align:center;">
        <a href="#subscribe" class="btn btn-primary">
          Start your 30-day story
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14M13 6l6 6-6 6"/></svg>
        </a>
      </div>
    </div>
  </section>

  <!-- ===== Caretaker section — connected care ===== -->
  <section id="caretaker" class="section" style="background: rgba(255,255,255,0.4);">
    <div class="container">
      <div class="section-head">
        <span class="section-eyebrow">Caretaker</span>
        <h2>Be there, even when you can't be there</h2>
        <p class="sub">
          Share your 6-character code with the people you look after. Once they accept,
          their meals, workout, water, medicine and mood show up live in your dashboard —
          so a quick glance tells you exactly how they are doing today.
        </p>
      </div>

      <!-- Horizontal scroll row of caregiver screenshot cards.
           Same image + bangla heading + body pairing as before,
           but the row scrolls horizontally instead of wrapping
           into a tall grid — keeps the page compact. -->
      <div class="hscroll fade-up">
        <div class="hscroll-care-card">
          <div class="frame">
            <img src="images/caretaker-home.png" alt="Caretaker home — patient cards and services" loading="lazy" />
          </div>
          <h3>সবকিছু এক নজরে</h3>
          <p>
            Greeting, রোগীর কার্ড, এবং পরিষেবা বিভাগ একই স্ক্রিনে।
            আজকের অনুরোধ, বিজ্ঞপ্তি এবং নোটিশ একই জায়গায়।
          </p>
        </div>

        <div class="hscroll-care-card">
          <div class="frame">
            <img src="images/caretaker-patient-home.png" alt="Patient's daily progress as seen from the caretaker app" loading="lazy" />
          </div>
          <h3>রোগীর দৈনিক অগ্রগতি দেখুন</h3>
          <p>
            পানি, খাবার, ওষুধ, ব্যায়াম এবং মেজাজ — রোগী কী অর্জন করেছে,
            কী বাকি, সব এক নজরে। আপডেট হয় realtime-এ।
          </p>
        </div>

        <div class="hscroll-care-card">
          <div class="frame">
            <img src="images/caretaker-services.png" alt="All 8 caretaker service tiles for a single patient" loading="lazy" />
          </div>
          <h3>রোগীর সব দেখুন — ৮টি টাইলে</h3>
          <p>
            সম্পূর্ণ প্রোফাইল, খাবারের পরিকল্পনা, পানির খতিয়ান, পানি বিশ্লেষণ,
            ওষুধের সময়সূচী, ব্যায়াম তালিকা, বিশ্লেষণ এবং ডাক্তারের প্রতিবেদন।
          </p>
        </div>

        <div class="hscroll-care-card">
          <div class="frame">
            <img src="images/caretaker-inbox.png" alt="Apon Inbox — empty state" loading="lazy" />
          </div>
          <h3>অনুরোধ পাঠান — গুনগুন করে</h3>
          <p>
            অ্যাপন ইনবক্স থেকে রোগীর কাছে ছোট ছোট অনুরোধ পাঠান —
            পানি খেতে বলুন, ওষুধ নিতে বলুন, আজকের খাবার চেক করুন।
          </p>
        </div>
      </div>

      <p style="text-align: center; font-size: 12.5px; color: var(--text-hint); margin-top: -8px;">
        ← বামে-ডানে স্ক্রল করুন →
      </p>

      <div style="text-align:center; margin-top: 40px;">
        <p class="sub" style="margin: 0 0 18px;">
          Subscribe once → install once → use it as a patient or switch to caretaker with the same login.
        </p>
        <a href="#subscribe" class="btn btn-primary">
          Subscribe &amp; look after someone today
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14M13 6l6 6-6 6"/></svg>
        </a>
      </div>
    </div>
  </section>

  <!-- ===== Voice — record, schedule, listen, reply ===== -->
  <section id="voice" class="section">
    <div class="container">
      <div class="section-head">
        <span class="section-eyebrow">Voice messages</span>
        <h2>প্রিয়জনের গলা — যখন খুশি, যতবার খুশি</h2>
        <p class="sub">
          পরিচর্যাকারী মাইকে চেপে একটু ভালোবাসা পাঠান — সময় ঠিক করে দিন, ঠিকানায় পৌঁছে যাবে।
          রোগী শুনুন, চাইলে ভয়েসে উত্তরও দিন।
        </p>
      </div>

      <div class="voice-grid fade-up">
        <!-- Left: phone-frame with the record.png image. -->
        <div class="voice-image-wrap">
          <div class="voice-image-frame">
            <img src="images/record.png" alt="Voice recording screen — record and send" loading="lazy" />
          </div>
          <!-- Animated pulse dot — visually echoes the in-app mic recording state. -->
          <div class="pulse" aria-hidden="true"></div>
        </div>

        <!-- Right: 4-step flow covering BOTH directions
             (caretaker → patient AND patient → caretaker reply). -->
        <div>
          <div class="voice-flow">
            <div class="voice-step">
              <div class="voice-num">1</div>
              <div>
                <h4>পরিচর্যাকারী রেকর্ড করেন</h4>
                <p>ভয়েস ব্যানার থেকে রোগী বাছাই করে মাইকে চাপ দিন — ১ মিনিট পর্যন্ত।</p>
              </div>
            </div>
            <div class="voice-step">
              <div class="voice-num">2</div>
              <div>
                <h4>সময় ঠিক করে পাঠান</h4>
                <p>আজ রাত ৮টায়? কাল সকালে? টাইমজোন সহ নির্বাচন করুন — পরিষেবা নিজেই ঠিক ঠিকানায় পৌঁছে দেবে।</p>
              </div>
            </div>
            <div class="voice-step">
              <div class="voice-num">3</div>
              <div>
                <h4>রোগী শোনেন</h4>
                <p>রোগীর ইনবক্সে ভয়েস পৌঁছে যায় — শুনুন, প্রিয়জনের গলা একটু কাছে আসে।</p>
              </div>
            </div>
            <div class="voice-step">
              <div class="voice-num">4</div>
              <div>
                <h4>রোগী ভয়েসে উত্তর দেন</h4>
                <p>চাইলে রোগীও মাইকে চেপে উত্তর দিতে পারেন — পরিচর্যাকারীর কাছে সরাসরি পৌঁছে যাবে।</p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </section>

  <!-- ===== Subscribe / status / unsubscribe portal ===== -->
  <section id="subscribe" class="section">
    <div class="container">
      <div class="section-head">
        <span class="section-eyebrow">Subscribe &amp; Manage</span>
        <h2>Subscribe or check your subscription</h2>
        <p class="sub">
          Subscribe directly from this page or check whether your number is already active.
          Charges appear on your <?php echo htmlspecialchars($PRICE_OPERATOR); ?> mobile bill.
        </p>
      </div>

      <div class="portal-grid">

        <!-- ----- Check subscription status ----- -->
        <div class="portal-card">
          <div class="portal-icon">
            <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>
          </div>
          <h3>Check subscription status</h3>
          <p class="portal-sub">Enter your Robi / Cirkle mobile number to see if you are currently subscribed.</p>

          <div class="form-group">
            <label for="status-phone">Mobile Number</label>
            <input type="tel" id="status-phone" placeholder="01XXXXXXXXX" maxlength="14" />
          </div>

          <button id="btn-check-status" class="btn btn-primary btn-full" onclick="checkStatus()">Check status</button>
          <div id="status-result" class="status-result" aria-live="polite"></div>

          <p class="charge-disclaimer"><?php echo htmlspecialchars($CHARGE_DISCLAIMER); ?></p>
        </div>

        <!-- ----- Subscribe (new user) ----- -->
        <div class="portal-card portal-card-feature">
          <div class="badge">New user</div>
          <div class="portal-icon">
            <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2 4 6v6c0 5 3.5 9.5 8 10 4.5-.5 8-5 8-10V6l-8-4z"/></svg>
          </div>
          <h3>Subscribe to <?php echo htmlspecialchars($APP_NAME); ?></h3>
          <p class="portal-sub">
            Enter your Robi / Cirkle mobile number. We'll send a one-time PIN — confirm it to start your subscription.
          </p>

          <div id="subscribe-step-phone" class="subscribe-step">
            <div class="form-group">
              <label for="sub-phone">Mobile Number</label>
              <input type="tel" id="sub-phone" placeholder="01XXXXXXXXX" maxlength="14" />
            </div>
            <button id="btn-send-otp" class="btn btn-primary btn-full" onclick="requestOtp()">
              Send OTP
            </button>
          </div>

          <div id="subscribe-step-otp" class="subscribe-step" style="display:none;">
            <p class="otp-hint">A 6-digit OTP has been sent to your phone via SMS. Enter it below to confirm your subscription.</p>
            <div class="form-group">
              <label for="otp-code">6-digit OTP</label>
              <input type="text" id="otp-code" inputmode="numeric" maxlength="6" placeholder="••••••" />
            </div>
            <button id="btn-verify-otp" class="btn btn-primary btn-full" onclick="verifyOtp()">
              Verify &amp; subscribe
            </button>
            <button class="btn btn-ghost btn-full" style="margin-top:10px;" onclick="resetSubscribe()">
              Change number
            </button>
          </div>

          <p id="sub-message" class="status-result" aria-live="polite"></p>

          <p class="charge-disclaimer"><?php echo htmlspecialchars($CHARGE_DISCLAIMER); ?></p>
        </div>

        <!-- ----- Unsubscribe ----- -->
        <div class="portal-card">
          <div class="portal-icon portal-icon-coral">
            <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M18.36 6.64A9 9 0 1 1 5.64 6.64"/><path d="M12 2v10"/></svg>
          </div>
          <h3>Unsubscribe</h3>
          <p class="portal-sub">To stop your subscription, dial <strong>*213*01085#</strong> from your Robi / Cirkle number, or use the BDApps portal.</p>

          <div class="form-group">
            <label for="unsub-phone">Mobile Number</label>
            <input type="tel" id="unsub-phone" placeholder="01XXXXXXXXX" maxlength="14" />
          </div>

          <button id="btn-unsubscribe" class="btn btn-coral btn-full" onclick="unsubscribe()">
            Request unsubscribe
          </button>
          <p id="unsub-message" class="status-result" aria-live="polite"></p>

          <p class="charge-disclaimer"><?php echo htmlspecialchars($CHARGE_DISCLAIMER); ?></p>
        </div>

      </div>

      <div class="cta">
        <div class="cta-inner">
          <h2>Ready to take control of your everyday health?</h2>
          <p><?php echo htmlspecialchars($CHARGE_DISCLAIMER); ?></p>
          <div class="btn-row">
            <a href="#subscribe-step-phone" onclick="document.getElementById('sub-phone').focus(); return true;" class="btn">
              Subscribe now
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14M13 6l6 6-6 6"/></svg>
            </a>
            <a href="<?php echo htmlspecialchars($APK_DOWNLOAD_URL); ?>" class="btn btn-ghost">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4M7 10l5 5 5-5M12 15V3"/></svg>
              Download APK
            </a>
          </div>
        </div>
      </div>
    </div>
  </section>

  <!-- ===== Footer ===== -->
  <footer class="footer">
    <div class="container">
      <div class="footer-brand">
        <img src="images/logo.png" alt="<?php echo htmlspecialchars($APP_NAME); ?>" />
        <span><?php echo htmlspecialchars($APP_NAME); ?></span>
      </div>
      <p>
        <strong><?php echo htmlspecialchars($APP_NAME); ?></strong> · <strong><?php echo htmlspecialchars($APP_NAME_EN); ?></strong> · App ID:
        <code><?php echo htmlspecialchars($APP_ID); ?></code> ·
        Category: <strong><?php echo htmlspecialchars($APP_CATEGORY); ?></strong> ·
        Available on <?php echo htmlspecialchars(implode(' &amp; ', $PLATFORMS)); ?>
      </p>
      <p class="small">
        <a href="<?php echo htmlspecialchars($PRIVACY_URL); ?>">Privacy</a> ·
        <a href="<?php echo htmlspecialchars($FAQ_URL); ?>">FAQ</a> ·
        For support, email <a href="mailto:<?php echo htmlspecialchars($SUPPORT_EMAIL); ?>"><?php echo htmlspecialchars($SUPPORT_EMAIL); ?></a>
        or call <?php echo htmlspecialchars($SUPPORT_PHONE); ?>.
      </p>
      <p class="small">
        © <?php echo date('Y'); ?> <?php echo htmlspecialchars($APP_NAME); ?>.
        Subscription handled by BDApps. All charges (incl. Vat+SC+SD) appear on your mobile bill.
        Operated by <strong><?php echo htmlspecialchars($PRICE_OPERATOR); ?></strong>.
      </p>
      <p class="small">
        Subscription response message includes the
        <strong><?php echo htmlspecialchars($APP_CATEGORY); ?></strong> category and the
        <a href="<?php echo htmlspecialchars($APK_DOWNLOAD_URL); ?>">official APK link</a>.
      </p>
    </div>
  </footer>

<script>
  // -------------------------------------------------------------
  // Shared helpers (identical contract to landingpagehelper)
  // -------------------------------------------------------------
  let currentRef = '';
  let busy = false;

  function normalizeBD(raw) {
    let d = (raw || '').replace(/\D+/g, '');
    if (d.startsWith('880') && d.length === 13) d = '0' + d.slice(3);
    else if (d.startsWith('88')  && d.length === 12) d = '0' + d.slice(2);
    return d;
  }

  function setBusy(btn, on, label) {
    const orig = btn.dataset.label || btn.innerText;
    if (!btn.dataset.label) btn.dataset.label = orig;
    btn.disabled = !!on;
    btn.innerText = on ? (label || 'Please wait…') : orig;
    busy = !!on;
  }

  // -------------------------------------------------------------
  // Check subscription status
  //
  // Mirrors the rich result card in
  // `lib/screens/auth/subscription_check_screen.dart` so web users
  // see exactly the same detail (verdict, status headline,
  // statusCode, statusDetail, message + raw JSON) as in-app users.
  // -------------------------------------------------------------
  async function checkStatus() {
    if (busy) return;
    const raw = document.getElementById('status-phone').value;
    const num = normalizeBD(raw);
    const out = document.getElementById('status-result');
    const btn = document.getElementById('btn-check-status');

    if (!/^01[3-9][0-9]{8}$/.test(num)) {
      out.innerHTML = '<span class="status-pill status-err">Please enter a valid BD mobile number (01XXXXXXXXX).</span>';
      return;
    }

    out.innerHTML = '<span class="status-pill status-wait">Checking…</span>';
    setBusy(btn, true, 'Checking…');

    try {
      const fd = new FormData();
      fd.append('user_mobile', num);
      // Production contract — check_subscription.php returns
      // { subscriptionStatus: 'REGISTERED'|'UNREGISTERED', isSubscribed: bool, ... }
      const r   = await fetch('check_subscription.php', { method: 'POST', body: fd });
      const data = await r.json();

      out.innerHTML = renderStatusResult(num, data);
    } catch (e) {
      out.innerHTML =
        '<div class="result-card is-error">'
        + '<div class="result-card-head">'
        +   '<div class="result-card-icon">' + iconError() + '</div>'
        +   '<div class="result-card-text">'
        +     '<div class="result-card-verdict">লুকআপ ব্যর্থ</div>'
        +     '<div class="result-card-headline">Could not reach the server</div>'
        +   '</div>'
        + '</div>'
        + '<div class="result-row"><div class="result-row-label">নম্বর</div>'
        +   '<div class="result-row-value">' + escapeHtml(num) + '</div></div>'
        + '</div>';
    } finally {
      setBusy(btn, false);
    }
  }

  // -------------------------------------------------------------
  // Result-card renderer — mirrors SubscriptionCheckScreen._ResultCard.
  // -------------------------------------------------------------
  function renderStatusResult(num, data) {
    const status = (data && data.subscriptionStatus ? String(data.subscriptionStatus) : '').toUpperCase();
    const statusCode = data && data.statusCode ? String(data.statusCode) : '';
    const statusDetail = data && data.statusDetail ? String(data.statusDetail) : '';
    const message = data && data.message ? String(data.message) : '';

    // isUserActive parity with lib/services/bdapps/bdapps_service.dart
    const isActive = status && status !== 'UNREGISTERED';
    const hasUsableStatus = !!status;
    const isError = !hasUsableStatus && (data && (data.error || (statusCode && !statusCode.toUpperCase().startsWith('S'))));

    let cardClass = 'result-card';
    if (isError)            cardClass += ' is-error';
    else if (isActive)      cardClass += ' is-active';
    else                    cardClass += ' is-inactive';

    let verdict, headline, icon;
    if (isError) {
      verdict  = 'লুকআপ ব্যর্থ';
      headline = statusCode || 'Lookup failed';
      icon     = iconError();
    } else if (isActive) {
      verdict  = 'সক্রিয় সাবস্ক্রিপশন';
      headline = status || 'লুকআপ সম্পন্ন';
      icon     = iconCheck();
    } else {
      verdict  = 'সাবস্ক্রিপশন নেই';
      headline = status || 'UNREGISTERED';
      icon     = iconCancel();
    }

    let html = '<div class="' + cardClass + '">';
    html += '<div class="result-card-head">';
    html +=   '<div class="result-card-icon">' + icon + '</div>';
    html +=   '<div class="result-card-text">';
    html +=     '<div class="result-card-verdict">' + escapeHtml(verdict) + '</div>';
    html +=     '<div class="result-card-headline">' + escapeHtml(headline) + '</div>';
    html +=   '</div>';
    html += '</div>';

    html += '<div class="result-row"><div class="result-row-label">নম্বর</div>'
         +  '<div class="result-row-value">' + escapeHtml(num) + '</div></div>';

    if (statusCode) {
      html += '<div class="result-row"><div class="result-row-label">statusCode</div>'
           +  '<div class="result-row-value">' + escapeHtml(statusCode) + '</div></div>';
    }
    if (statusDetail) {
      html += '<div class="result-row"><div class="result-row-label">statusDetail</div>'
           +  '<div class="result-row-value">' + escapeHtml(statusDetail) + '</div></div>';
    }
    if (message) {
      html += '<div class="result-row"><div class="result-row-label">message</div>'
           +  '<div class="result-row-value">' + escapeHtml(message) + '</div></div>';
    }

    html += '<div class="result-helper">REGISTERED / GRACE মানে আপনার সাবস্ক্রিপশন সক্রিয়। UNREGISTERED মানে আবার সাবস্ক্রাইব করা প্রয়োজন।</div>';
    html += '</div>';
    return html;
  }

  function iconCheck() {
    return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg>';
  }
  function iconCancel() {
    return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="M18 6 6 18M6 6l12 12"/></svg>';
  }
  function iconError() {
    return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M12 8v4M12 16h.01"/></svg>';
  }

  function escapeHtml(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  // -------------------------------------------------------------
  // Subscribe — request OTP
  // -------------------------------------------------------------
  async function requestOtp() {
    if (busy) return;
    const raw = document.getElementById('sub-phone').value;
    const num = normalizeBD(raw);
    const msg = document.getElementById('sub-message');
    const btn = document.getElementById('btn-send-otp');

    if (!/^01[3-9][0-9]{8}$/.test(num)) {
      msg.innerHTML = '<span class="status-pill status-err">Please enter a valid BD mobile number (01XXXXXXXXX).</span>';
      return;
    }

    msg.innerHTML = '<span class="status-pill status-wait">Checking subscription…</span>';
    setBusy(btn, true, 'Checking…');

    try {
      const fd = new FormData();
      fd.append('user_mobile', num);
      const r    = await fetch('send_otp.php', { method: 'POST', body: fd });
      const data = await r.json();

      if (data.success && data.referenceNo) {
        currentRef = data.referenceNo;
        document.getElementById('subscribe-step-phone').style.display = 'none';
        document.getElementById('subscribe-step-otp').style.display  = 'block';
        document.getElementById('otp-code').focus();
        msg.innerHTML = '<span class="status-pill status-ok">OTP sent. Check your SMS inbox.</span>';
      } else {
        const detail = (data.message || '').toLowerCase();
        if (detail.includes('already registered') || detail.includes('already subscribed')) {
          msg.innerHTML = '<span class="status-pill status-ok">You are already subscribed ✓</span>';
        } else {
          msg.innerHTML = '<span class="status-pill status-err">' + (data.message || 'Could not send OTP. Try again later.') + '</span>';
        }
      }
    } catch (e) {
      msg.innerHTML = '<span class="status-pill status-err">Could not reach the server. Please try again.</span>';
    } finally {
      setBusy(btn, false);
    }
  }

  function resetSubscribe() {
    currentRef = '';
    document.getElementById('subscribe-step-phone').style.display = 'block';
    document.getElementById('subscribe-step-otp').style.display  = 'none';
    document.getElementById('sub-message').innerHTML = '';
    document.getElementById('otp-code').value = '';
    document.getElementById('sub-phone').focus();
  }

  // -------------------------------------------------------------
  // Subscribe — verify OTP
  // -------------------------------------------------------------
  async function verifyOtp() {
    if (busy) return;
    const otp = document.getElementById('otp-code').value.trim();
    const msg = document.getElementById('sub-message');
    const btn = document.getElementById('btn-verify-otp');

    if (!/^\d{6}$/.test(otp)) {
      msg.innerHTML = '<span class="status-pill status-err">Please enter the 6-digit OTP from SMS.</span>';
      return;
    }
    if (!currentRef) {
      msg.innerHTML = '<span class="status-pill status-err">Session expired. Please request a new OTP.</span>';
      return;
    }

    msg.innerHTML = '<span class="status-pill status-wait">Verifying…</span>';
    setBusy(btn, true, 'Verifying…');

    try {
      const fd = new FormData();
      fd.append('user_mobile', normalizeBD(document.getElementById('sub-phone').value));
      fd.append('referenceNo', currentRef);
      fd.append('otp', otp);

      const r    = await fetch('verify_otp.php', { method: 'POST', body: fd });
      const data = await r.json();

      if (data.statusCode === 'S1000' || (data.subscriptionStatus && String(data.subscriptionStatus).toUpperCase() === 'REGISTERED')) {
        msg.innerHTML = '<span class="status-pill status-ok">Subscription confirmed ✓</span>'
          + '<p class="status-detail">You can now download and log in to ' + '<?php echo $APP_NAME; ?>' + '.</p>';
      } else {
        msg.innerHTML = '<span class="status-pill status-err">'
          + (data.statusDetail || data.message || 'Invalid OTP. Try again.')
          + '</span>';
      }
    } catch (e) {
      msg.innerHTML = '<span class="status-pill status-err">Could not reach the server. Please try again.</span>';
    } finally {
      setBusy(btn, false);
    }
  }

  // -------------------------------------------------------------
  // Unsubscribe
  // -------------------------------------------------------------
  async function unsubscribe() {
    if (busy) return;
    const raw = document.getElementById('unsub-phone').value;
    const num = normalizeBD(raw);
    const msg = document.getElementById('unsub-message');
    const btn = document.getElementById('btn-unsubscribe');

    if (!/^01[3-9][0-9]{8}$/.test(num)) {
      msg.innerHTML = '<span class="status-pill status-err">Please enter a valid BD mobile number (01XXXXXXXXX).</span>';
      return;
    }

    msg.innerHTML = '<span class="status-pill status-wait">Submitting…</span>';
    setBusy(btn, true, 'Submitting…');

    try {
      const fd = new FormData();
      fd.append('user_mobile', num);
      const r    = await fetch('unsubscribe.php', { method: 'POST', body: fd });
      const data = await r.json();

      if (data.success) {
        msg.innerHTML = '<span class="status-pill status-ok">Unsubscribe request submitted ✓</span>'
          + '<p class="status-detail">You will receive an SMS confirmation shortly.</p>';
      } else {
        msg.innerHTML = '<span class="status-pill status-err">'
          + (data.error || data.message || data.statusDetail || 'Could not submit unsubscribe request.')
          + '</span>';
      }
    } catch (e) {
      msg.innerHTML = '<span class="status-pill status-err">Could not reach the server. Please try again.</span>';
    } finally {
      setBusy(btn, false);
    }
  }

  // -------------------------------------------------------------
  // Subtle scroll-reveal
  //
  // We tag elements with `.fade-up` so they animate in from
  // opacity:0 -> opacity:1 as they enter the viewport.
  //
  // CRITICAL: we MUST only mark elements as `.fade-up` when we
  // know the IntersectionObserver can also reveal them — otherwise
  // the elements stay invisible forever (opacity:0).
  //
  // MOBILE-FIRST SAFETY: many mobile WebView / low-end Android
  // browsers have slow or sticky IntersectionObserver implementations
  // that can leave sections stuck at opacity:0. So on any
  // viewport ≤ 820px we skip the fade-up entirely and reveal
  // everything immediately. The nice scroll-in animation runs
  // only on desktop.
  // -------------------------------------------------------------
  const REVEAL_SELECTOR =
    '.feature-card, .hscroll-feature, .hscroll-care-card, .hscroll-img-card, ' +
    '.step, .stat-card, .dp-cell, .shot, .daily-progress, .voice-step';

  // 1) Always reveal elements immediately (no animation).
  //    Used on mobile AND as the fallback for desktop.
  function revealAllNow() {
    document.querySelectorAll(REVEAL_SELECTOR).forEach((el) => {
      el.classList.add('in');
      el.classList.remove('fade-up');
    });
  }

  const isMobile =
    window.matchMedia &&
    window.matchMedia('(max-width: 820px)').matches;

  const prefersReduce =
    window.matchMedia &&
    window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  // 2) Mobile / reduced-motion / no-IntersectionObserver →
  //    reveal everything immediately.
  if (
    isMobile ||
    prefersReduce ||
    !('IntersectionObserver' in window)
  ) {
    revealAllNow();
  } else {
    // 3) Desktop — wire up the reveal animation.
    document.documentElement.classList.add('js-reveal');

    const io = new IntersectionObserver((entries) => {
      entries.forEach((e) => {
        if (e.isIntersecting) {
          e.target.classList.add('in');
          io.unobserve(e.target);
        }
      });
    }, { threshold: 0.05, rootMargin: '0px 0px -5% 0px' });

    const revealTargets = document.querySelectorAll(REVEAL_SELECTOR);
    revealTargets.forEach((el) => {
      el.classList.add('fade-up');
      io.observe(el);
    });

    // 4) Safety net 1: after layout, reveal anything already in view.
    requestAnimationFrame(() => {
      revealTargets.forEach((el) => {
        if (el.classList.contains('in')) return;
        const r = el.getBoundingClientRect();
        const visible = r.top < window.innerHeight && r.bottom > 0;
        if (visible) {
          el.classList.add('in');
          io.unobserve(el);
        }
      });
    });

    // 5) Safety net 2: scroll-driven fallback (in case IO fails
    //    silently). Reveals anything within 200px of the viewport.
    let scrollTick = false;
    function onScroll() {
      if (scrollTick) return;
      scrollTick = true;
      requestAnimationFrame(() => {
        scrollTick = false;
        revealTargets.forEach((el) => {
          if (el.classList.contains('in')) return;
          const r = el.getBoundingClientRect();
          if (r.top < window.innerHeight + 200 && r.bottom > -200) {
            el.classList.add('in');
            io.unobserve(el);
          }
        });
      });
    }
    window.addEventListener('scroll', onScroll, { passive: true });
    window.addEventListener('resize', onScroll, { passive: true });
    // Fire once after layout settles to catch anything IO missed.
    requestAnimationFrame(onScroll);

    // 6) Hard fallback: at 1.5s and 3s, flip on everything left.
    [1500, 3000].forEach((delay) => {
      setTimeout(() => {
        document.querySelectorAll(REVEAL_SELECTOR + '.fade-up:not(.in)').forEach((el) => {
          el.classList.add('in');
          io.unobserve(el);
        });
      }, delay);
    });

    // 7) Cross-device safety: if the user resizes / rotates
    //    into a mobile viewport after we've already started the
    //    desktop reveal, reveal anything left immediately.
    window.addEventListener('resize', () => {
      if (window.matchMedia('(max-width: 820px)').matches) {
        document.querySelectorAll(REVEAL_SELECTOR + '.fade-up:not(.in)').forEach((el) => {
          el.classList.add('in');
          io.unobserve(el);
        });
      }
    });
  }
</script>

</body>
</html>
