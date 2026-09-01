<?php
/**
 * Amar Diet — Landing Page & Subscription Portal
 * BDApps-compliant landing page for the Amar Diet app.
 *
 * Place this file (and the `assets/` folder next to it) into your cPanel
 * account under the same folder that BDApps will point to.
 *
 * The subscription backend scripts (send_otp.php, verify_otp.php,
 * check_subscription.php, unsubscribe.php) MUST live in the same folder.
 *
 * Configuration: edit the constants below to match your BDApps submission.
 */

$APP_ID           = 'NADB26045';                    // BDApps App ID (used in URL)
$APP_ID_INTERNAL  = 'APP_139165';                   // BDApps internal App ID for API calls
$APP_NAME         = 'Amar Diet';                    // APK name (must match Pro app name)
$APP_NAME_BN      = 'আমার ডায়েট';                   // Bangla name
$TAGLINE          = 'Your Bangladeshi diet coach';
$TAGLINE_BN       = 'বাংলাদেশি খাবারের স্মার্ট ডায়েট কোচ';

// App category — Health & Fitness. Must match what BDApps has on file
// for the subscription response message.
$APP_CATEGORY     = 'Health & Fitness';

// APK lives on the same cPanel account under the app's folder.
$APK_DOWNLOAD_URL = 'https://bdappsdigitalapps.com/' . $APP_ID . '/apk/amar_diet.apk';

// BDApps subscription portal (used for the Unsubscribe CTA link only —
// subscribe happens right here on this page).
$UNSUBSCRIBE_URL  = 'https://bdappsdigitalapps.com/subscription/manage?app=' . $APP_ID;

$SUPPORT_EMAIL    = 'support@bdapps.com';
// Privacy / FAQ anchors. These open a modal on this same page so the
// user never sees a broken `#` link. The modal content below the page
// renders the same text from the FAQ file you submitted to BDApps.
$PRIVACY_URL      = '#privacy';
$FAQ_URL          = '#faq';
$SUPPORT_PHONE    = '+8809610999922';

// Pricing — must match the FAQ and the in-app Subscription screen.
$PRICE_DAILY_BDT       = '2.78';   // daily charge (incl. Vat+SC+SD)
$PRICE_BUNDLED_BDT     = '5.56';   // bundled 5-day equivalent (context only)
$PRICE_MONTHLY_BDT     = '299';    // ৳ per month when paid monthly
$PRICE_YEARLY_BDT      = '199';    // ৳ per month when paid yearly
$PRICE_OPERATOR        = 'Robi and Airtel';

// The mandatory disclosure that MUST appear under every subscription option.
$CHARGE_DISCLAIMER = 'Subscribe now for ৳' . $PRICE_DAILY_BDT
                   . ' / day (incl. Vat+SC+SD) on ' . $PRICE_OPERATOR
                   . ' and unlock the full ' . $APP_NAME . ' experience.';

// Platforms — Android only.
$PLATFORMS = ['Android'];
?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <meta name="theme-color" content="#10B981" />
  <title><?php echo htmlspecialchars($APP_NAME); ?> — <?php echo htmlspecialchars($TAGLINE); ?></title>
  <meta name="description" content="<?php echo htmlspecialchars($APP_NAME); ?> helps you plan meals, track calories, and reach your health goals with Bangladeshi-first food data. Subscribe and start today." />

  <link rel="preconnect" href="https://fonts.googleapis.com" />
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
  <link href="https://fonts.googleapis.com/css2?family=Roboto:wght@400;500;600;700;800&display=swap" rel="stylesheet" />

  <link rel="stylesheet" href="assets/css/style.css?v=20260728" />
  <link rel="icon" type="image/png" href="assets/img/favicon.png" />
</head>
<body>

  <!-- ===== Navigation ===== -->
  <nav class="nav">
    <div class="nav-inner">
      <a href="#top" class="brand">
        <span class="brand-logo">🥗</span>
        <span><?php echo htmlspecialchars($APP_NAME); ?></span>
      </a>
      <ul class="nav-links">
        <li><a href="#features">Features</a></li>
        <li><a href="#screens">Screens</a></li>
        <li><a href="#pricing">Pricing</a></li>
        <li><a href="#how">How it works</a></li>
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
            Eat smart.<br />
            Live <span class="accent">Bangladeshi.</span>
          </h1>
          <p class="lead">
            <?php echo htmlspecialchars($APP_NAME); ?> is a diet and meal-tracking app built around the foods
            you actually eat — from plain rice and hilsa curry to biryani and khichuri.
            Plan meals, track calories, and reach your goal with daily guidance.
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
              <div class="title">Daily calories</div>
              <div class="value">1,420 / 2,000</div>
            </div>
          </div>

          <div class="hero-floating hero-floating-2">
            <div class="icon-bubble coral">
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2v6M12 16v6M4.93 4.93l4.24 4.24M14.83 14.83l4.24 4.24M2 12h6M16 12h6M4.93 19.07l4.24-4.24M14.83 9.17l4.24-4.24"/></svg>
            </div>
            <div>
              <div class="title">Water today</div>
              <div class="value">1.8 / 2.5 L</div>
            </div>
          </div>

          <div class="phone">
            <img src="assets/img/Screenshot_20260726_114643.png" alt="<?php echo htmlspecialchars($APP_NAME); ?> app preview" />
          </div>
        </div>
      </div>
    </div>
  </header>

  <!-- ===== Platforms ===== -->
  <section class="section" style="padding-top: 0;">
    <div class="container">
      <div class="stats">
        <div class="stat-card">
          <div class="num">20+</div>
          <div class="label">BD Foods</div>
        </div>
        <div class="stat-card">
          <div class="num">7-Day</div>
          <div class="label">Plans</div>
        </div>
        <div class="stat-card">
          <div class="num">Daily</div>
          <div class="label">Tracking</div>
        </div>
        <div class="stat-card">
          <div class="num">100%</div>
          <div class="label">Private</div>
        </div>
      </div>
    </div>
  </section>

  <!-- ===== Features ===== -->
  <section id="features" class="section">
    <div class="container">
      <div class="section-head">
        <span class="section-eyebrow">Features</span>
        <h2>Everything you need to stay on track</h2>
        <p class="sub">
          Built around Bangladeshi meals — not imported Western food data.
          Track, plan, and improve every day.
        </p>
      </div>

      <div class="features-grid">
        <div class="feature-card">
          <div class="feature-icon">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18M3 12h18M3 18h18"/></svg>
          </div>
          <h3>Bangladeshi food library</h3>
          <p>Browse and log meals from rice, roti, fish, meat, daal, fruits, and snacks — with accurate calorie and macro data.</p>
        </div>

        <div class="feature-card coral">
          <div class="feature-icon">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M12 6v6l4 2"/></svg>
          </div>
          <h3>Daily calorie target</h3>
          <p>Your BMR, TDEE, and goal-based calorie target are calculated automatically — lose, maintain, or gain.</p>
        </div>

        <div class="feature-card solid">
          <div class="feature-icon">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2v4M12 18v4M4.93 4.93l2.83 2.83M16.24 16.24l2.83 2.83M2 12h4M18 12h4M4.93 19.07l2.83-2.83M16.24 7.76l2.83-2.83"/></svg>
          </div>
          <h3>Water tracker</h3>
          <p>Quick-add glasses and cups. Hit your daily hydration goal with simple visual feedback.</p>
        </div>

        <div class="feature-card">
          <div class="feature-icon">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M3 3v18h18"/><path d="M7 14l4-4 4 4 5-5"/></svg>
          </div>
          <h3>Progress analytics</h3>
          <p>See your weekly calorie trend, macro split, and weight history — all in one clean dashboard.</p>
        </div>

        <div class="feature-card coral">
          <div class="feature-icon">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/></svg>
          </div>
          <h3>Smart recommendations</h3>
          <p>Swipe-based meal suggestions that match your goal, preferences, and the time of day.</p>
        </div>

        <div class="feature-card solid">
          <div class="feature-icon">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4" width="18" height="18" rx="2"/><path d="M16 2v4M8 2v4M3 10h18"/></svg>
          </div>
          <h3>Weekly planning</h3>
          <p>Set a weekly calorie and water goal, then check back to keep your streak alive.</p>
        </div>
      </div>
    </div>
  </section>

  <!-- ===== Screenshots ===== -->
  <section id="screens" class="section" style="background: rgba(255,255,255,0.4);">
    <div class="container">
      <div class="section-head">
        <span class="section-eyebrow">Screens</span>
        <h2>Take a peek inside</h2>
        <p class="sub">A clean, glassmorphism-first design that feels at home on any device.</p>
      </div>

      <div class="shots-row">
        <div class="shot"><img src="assets/img/Screenshot_20260726_114643.png" alt="Dashboard" /></div>
        <div class="shot"><img src="assets/img/Screenshot_20260726_114738.png" alt="Browse foods" /></div>
        <div class="shot"><img src="assets/img/Screenshot_20260726_114744.png" alt="Food detail" /></div>
        <div class="shot"><img src="assets/img/Screenshot_20260726_114752.png" alt="Profile" /></div>
        <div class="shot"><img src="assets/img/Screenshot_20260726_120035.png" alt="Plan" /></div>
        <div class="shot"><img src="assets/img/Screenshot_20260726_120129.png" alt="Progress" /></div>
        <div class="shot"><img src="assets/img/Screenshot_20260726_120136.png" alt="Water" /></div>
        <div class="shot"><img src="assets/img/Screenshot_20260726_120145.png" alt="Recommendations" /></div>
        <div class="shot"><img src="assets/img/Screenshot_20260726_120209.png" alt="Log meal" /></div>
        <div class="shot"><img src="assets/img/Screenshot_20260726_120218.png" alt="Settings" /></div>
      </div>
    </div>
  </section>

  <!-- ===== Pricing ===== -->
  <section id="pricing" class="section">
    <div class="container">
      <div class="section-head">
        <span class="section-eyebrow">Pricing</span>
        <h2>Simple, transparent pricing</h2>
        <p class="sub">
          All subscription charges are inclusive of Vat + SC + SD and are billed only to
          <strong><?php echo htmlspecialchars($PRICE_OPERATOR); ?></strong> users.
        </p>
      </div>

      <div class="pricing-wrap">
        <div class="pricing-card">
          <div class="tag">Monthly</div>
          <div class="price">৳<?php echo htmlspecialchars($PRICE_MONTHLY_BDT); ?></div>
          <div class="price-sub">
            Billed monthly
            <strong>৳<?php echo htmlspecialchars($PRICE_DAILY_BDT); ?> / day (incl. Vat+SC+SD)</strong>
          </div>
          <ul class="pricing-features">
            <li><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg> Full access to all Pro features</li>
            <li><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg> Bangladeshi food library</li>
            <li><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg> Daily calorie &amp; water tracking</li>
            <li><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg> Progress analytics</li>
          </ul>
          <a href="#subscribe" class="btn btn-primary">Subscribe monthly</a>
          <!-- Mandatory charge disclosure under every subscription option -->
          <p class="charge-disclaimer"><?php echo htmlspecialchars($CHARGE_DISCLAIMER); ?></p>
        </div>

        <div class="pricing-card featured">
          <div class="badge">Best value</div>
          <div class="tag">Yearly</div>
          <div class="price">৳<?php echo htmlspecialchars($PRICE_YEARLY_BDT); ?></div>
          <div class="price-sub">
            per month, billed yearly
            <strong>৳<?php echo htmlspecialchars($PRICE_DAILY_BDT); ?> / day (incl. Vat+SC+SD)</strong>
          </div>
          <ul class="pricing-features">
            <li><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg> Everything in Monthly</li>
            <li><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg> Save ~35% vs monthly</li>
            <li><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg> Smart meal recommendations</li>
            <li><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg> Weekly planning &amp; streaks</li>
            <li><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg> Priority support</li>
          </ul>
          <a href="#subscribe" class="btn btn-primary">Subscribe yearly</a>
          <!-- Mandatory charge disclosure under every subscription option -->
          <p class="charge-disclaimer"><?php echo htmlspecialchars($CHARGE_DISCLAIMER); ?></p>
        </div>
      </div>

      <p class="pricing-note">
        Bundled equivalent: <strong>৳<?php echo htmlspecialchars($PRICE_BUNDLED_BDT); ?> / 5 days</strong>.
        Auto-renews until canceled. Cancel anytime via BDApps portal.
        Subscriber must be on <strong><?php echo htmlspecialchars($PRICE_OPERATOR); ?></strong>.
      </p>

      <div class="notice">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M12 8v4M12 16h.01"/></svg>
        <div>
          To unsubscribe, dial <strong>*123*5#</strong> or visit the BDApps portal. Upon unsubscription
          you will be automatically logged out and redirected to the login page.
        </div>
      </div>
    </div>
  </section>

  <!-- ===== How it works ===== -->
  <section id="how" class="section" style="background: rgba(255,255,255,0.4);">
    <div class="container">
      <div class="section-head">
        <span class="section-eyebrow">How it works</span>
        <h2>Start in 3 simple steps</h2>
      </div>

      <div class="steps">
        <div class="step">
          <div class="step-num">1</div>
          <h3>Subscribe</h3>
          <p>Confirm via BDApps on your Robi or Airtel number. Charges appear as ৳<?php echo htmlspecialchars($PRICE_DAILY_BDT); ?> / day.</p>
        </div>
        <div class="step">
          <div class="step-num">2</div>
          <h3>Install &amp; log in</h3>
          <p>Download the APK, log in with your verified mobile number using BDApps OTP.</p>
        </div>
        <div class="step">
          <div class="step-num">3</div>
          <h3>Track &amp; improve</h3>
          <p>Set your goal, log meals, sip water, and watch your weekly progress climb.</p>
        </div>
      </div>
    </div>
  </section>

  <!-- ===== Subscribe & Status ===== -->
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
          <p class="portal-sub">Enter your Robi / Airtel mobile number to see if you are currently subscribed.</p>

          <div class="form-group">
            <label for="status-phone">Mobile Number</label>
            <input type="tel" id="status-phone" placeholder="01XXXXXXXXX" maxlength="14" />
          </div>

          <button id="btn-check-status" class="btn btn-primary btn-full" onclick="checkStatus()">Check status</button>
          <div id="status-result" class="status-result" aria-live="polite"></div>

          <!-- Mandatory charge disclosure -->
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
            Enter your Robi / Airtel mobile number. We'll send a one-time PIN — confirm it to start your subscription.
          </p>

          <!-- Step 1: phone -->
          <div id="subscribe-step-phone" class="subscribe-step">
            <div class="form-group">
              <label for="sub-phone">Mobile Number</label>
              <input type="tel" id="sub-phone" placeholder="01XXXXXXXXX" maxlength="14" />
            </div>
            <button id="btn-send-otp" class="btn btn-primary btn-full" onclick="requestOtp()">
              Send OTP
            </button>
          </div>

          <!-- Step 2: OTP -->
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

          <!-- Mandatory charge disclosure -->
          <p class="charge-disclaimer"><?php echo htmlspecialchars($CHARGE_DISCLAIMER); ?></p>
        </div>

        <!-- ----- Unsubscribe ----- -->
        <div class="portal-card">
          <div class="portal-icon portal-icon-coral">
            <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M18.36 6.64A9 9 0 1 1 5.64 6.64"/><path d="M12 2v10"/></svg>
          </div>
          <h3>Unsubscribe</h3>
          <p class="portal-sub">To stop your subscription, dial <strong>*123*5#</strong> from your Robi / Airtel number, or use the BDApps portal.</p>

          <div class="form-group">
            <label for="unsub-phone">Mobile Number</label>
            <input type="tel" id="unsub-phone" placeholder="01XXXXXXXXX" maxlength="14" />
          </div>

          <button id="btn-unsubscribe" class="btn btn-coral btn-full" onclick="unsubscribe()">
            Request unsubscribe
          </button>
          <p id="unsub-message" class="status-result" aria-live="polite"></p>

          <!-- Mandatory charge disclosure -->
          <p class="charge-disclaimer"><?php echo htmlspecialchars($CHARGE_DISCLAIMER); ?></p>
        </div>

      </div>

      <div class="cta">
        <div class="cta-inner">
          <h2>Ready to take control of your diet?</h2>
          <!-- Mandatory charge disclosure under the final subscribe CTA -->
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
      <p>
        <strong><?php echo htmlspecialchars($APP_NAME); ?></strong> · App ID:
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
  // Shared helpers
  // -------------------------------------------------------------
  let currentRef = '';     // OTP referenceNo for the active subscription
  let busy = false;        // prevent double-submits

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
  // -------------------------------------------------------------
  async function checkStatus() {
    if (busy) return;
    const raw  = document.getElementById('status-phone').value;
    const num  = normalizeBD(raw);
    const out  = document.getElementById('status-result');
    const btn  = document.getElementById('btn-check-status');

    if (!/^01[3-9][0-9]{8}$/.test(num)) {
      out.innerHTML = '<span class="status-pill status-err">Please enter a valid BD mobile number (01XXXXXXXXX).</span>';
      return;
    }

    out.innerHTML = '<span class="status-pill status-wait">Checking…</span>';
    setBusy(btn, true, 'Checking…');

    try {
      const fd = new FormData();
      fd.append('user_mobile', num);
      // Usingave send_otp.php as a more reliable status check
      const r   = await fetch('send_otp.php', { method: 'POST', body: fd });
      const data = await r.json();
      const msgText = (data.message || '').toLowerCase();

      if (msgText.includes('already registered') || msgText.includes('already subscribed')) {
        out.innerHTML = '<span class="status-pill status-ok">SUBSCRIBED ✓</span>'
          + '<p class="status-detail">Number <strong>0' + num.slice(-11) + '</strong> is currently registered.</p>';
      } else if (data.success) {
        // If success, it means user wasn't registered but now an OTP is sent
        out.innerHTML = '<span class="status-pill status-no">NOT SUBSCRIBED</span>'
          + '<p class="status-detail">Number <strong>0' + num.slice(-11) + '</strong> is not currently subscribed. An OTP has been sent to your phone to start.</p>';
        // Optionally shift UI to OTP verify if you want
      } else {
        out.innerHTML = '<span class="status-pill status-no">NOT SUBSCRIBED</span>'
          + '<p class="status-detail">Number <strong>0' + num.slice(-11) + '</strong> is not currently subscribed.</p>';
      }
    } catch (e) {
      out.innerHTML = '<span class="status-pill status-err">Could not reach the server. Please try again.</span>';
    } finally {
      setBusy(btn, false);
    }
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
        if(detail.includes('already registered') || detail.includes('already subscribed')) {
            msg.innerHTML = '<span class="status-pill status-ok" style="background:#10B981; color:white; font-size:1.1rem; padding:10px 20px;">SUCCESS — you are now subscribed 🥳</span><br><p class="status-detail" style="margin-top:10px;">Open the Amar Diet app and log in with this number to start.</p>';
            document.getElementById('subscribe-step-phone').style.display = 'none';
        } else {
            msg.innerHTML = '<span class="status-pill status-err">' + (data.message || 'Failed to send OTP.') + '</span>';
        }
      }
    } catch (e) {
      msg.innerHTML = '<span class="status-pill status-err">Could not reach the server. Please try again.</span>';
    } finally {
      setBusy(btn, false);
    }
  }

  // -------------------------------------------------------------
  // Subscribe — verify OTP
  // -------------------------------------------------------------
  async function verifyOtp() {
    if (busy) return;
    const otp = (document.getElementById('otp-code').value || '').trim();
    const msg = document.getElementById('sub-message');
    const btn = document.getElementById('btn-verify-otp');

    if (!otp || !/^\d{4,8}$/.test(otp)) {
      msg.innerHTML = '<span class="status-pill status-err">Please enter the OTP you received.</span>';
      return;
    }
    if (!currentRef) {
      msg.innerHTML = '<span class="status-pill status-err">Please request a new OTP first.</span>';
      return;
    }

    msg.innerHTML = '<span class="status-pill status-wait">Verifying…</span>';
    setBusy(btn, true, 'Verifying…');

    try {
      const fd = new FormData();
      fd.append('Otp', otp);
      fd.append('referenceNo', currentRef);
      const r    = await fetch('verify_otp.php', { method: 'POST', body: fd });
      const data = await r.json();

      const ok = (data.statusCode === 'S1000') ||
                 (data.subscriptionStatus && data.subscriptionStatus.toUpperCase() === 'REGISTERED');

      if (ok) {
        msg.innerHTML = '<span class="status-pill status-ok">SUCCESS — you are now subscribed 🎉</span>'
          + '<p class="status-detail">Open the Amar Diet app and log in with this number to start.</p>';
        document.getElementById('subscribe-step-otp').style.display = 'none';
      } else {
        msg.innerHTML = '<span class="status-pill status-err">' + (data.statusDetail || data.message || 'Invalid OTP.') + '</span>';
      }
    } catch (e) {
      msg.innerHTML = '<span class="status-pill status-err">Verification failed. Please try again.</span>';
    } finally {
      setBusy(btn, false);
    }
  }

  function resetSubscribe() {
    currentRef = '';
    document.getElementById('subscribe-step-otp').style.display  = 'none';
    document.getElementById('subscribe-step-phone').style.display = 'block';
    document.getElementById('otp-code').value = '';
    document.getElementById('sub-message').innerHTML = '';
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

    msg.innerHTML = '<span class="status-pill status-wait">Sending unsubscribe request…</span>';
    setBusy(btn, true, 'Sending…');

    try {
      const fd = new FormData();
      fd.append('user_mobile', num);
      const r    = await fetch('unsubscribe.php', { method: 'POST', body: fd });
      const data = await r.json();

      if (data.success) {
        msg.innerHTML = '<span class="status-pill status-ok">Unsubscribe request sent.</span>'
          + '<p class="status-detail">A confirmation SMS will be sent to your number. You can also dial <strong>*123*5#</strong>.</p>';
      } else {
        msg.innerHTML = '<span class="status-pill status-err">' + (data.statusDetail || data.error || 'Request failed.') + '</span>';
      }
    } catch (e) {
      msg.innerHTML = '<span class="status-pill status-err">Could not reach the server. Please try again.</span>';
    } finally {
      setBusy(btn, false);
    }
  }

  // -------------------------------------------------------------
  // Press Enter to submit
  // -------------------------------------------------------------
  document.addEventListener('keydown', function (e) {
    if (e.key !== 'Enter') return;
    const id = (document.activeElement && document.activeElement.id) || '';
    if (id === 'status-phone') { e.preventDefault(); checkStatus(); }
    else if (id === 'sub-phone') { e.preventDefault(); requestOtp(); }
    else if (id === 'otp-code') { e.preventDefault(); verifyOtp(); }
    else if (id === 'unsub-phone') { e.preventDefault(); unsubscribe(); }
  });

  // -------------------------------------------------------------
  // FAQ / Privacy modals (replaces the previous `#` placeholder)
  // -------------------------------------------------------------
  function openModal(id) {
    const m = document.getElementById(id);
    if (m) m.classList.add('open');
  }
  function closeModal(id) {
    const m = document.getElementById(id);
    if (m) m.classList.remove('open');
  }
  document.addEventListener('click', function (e) {
    if (e.target.classList && e.target.classList.contains('modal-backdrop')) {
      e.target.classList.remove('open');
    }
  });
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape') {
      document.querySelectorAll('.modal-backdrop.open').forEach(m => m.classList.remove('open'));
    }
  });
</script>

<!-- ===== FAQ Modal ===== -->
<div id="faq" class="modal-backdrop" role="dialog" aria-modal="true" aria-labelledby="faq-title">
  <div class="modal">
    <button class="modal-close" aria-label="Close" onclick="closeModal('faq')">&times;</button>
    <h2 id="faq-title">Frequently Asked Questions</h2>
    <p class="modal-sub">Category: <strong><?php echo htmlspecialchars($APP_CATEGORY); ?></strong> · Operator: <strong><?php echo htmlspecialchars($PRICE_OPERATOR); ?></strong></p>

    <h3>1. How much does <?php echo htmlspecialchars($APP_NAME); ?> cost?</h3>
    <p>৳<?php echo htmlspecialchars($PRICE_DAILY_BDT); ?> per day (incl. Vat+SC+SD) for Robi and Airtel users. Auto-renews daily until canceled.</p>

    <h3>2. Is there a bundled plan?</h3>
    <p>Yes — a bundled 5-day equivalent of ৳<?php echo htmlspecialchars($PRICE_BUNDLED_BDT); ?> is also available.</p>

    <h3>3. Which operators are supported?</h3>
    <p>Only <strong><?php echo htmlspecialchars($PRICE_OPERATOR); ?></strong> subscribers can subscribe. Other operators will be rejected by BDApps.</p>

    <h3>4. Where do I download the app?</h3>
    <p>Download the official APK from <a href="<?php echo htmlspecialchars($APK_DOWNLOAD_URL); ?>"><?php echo htmlspecialchars($APK_DOWNLOAD_URL); ?></a>. The app is available on Android only.</p>

    <h3>5. How do I unsubscribe?</h3>
    <p>Dial <strong>*123*5#</strong> from your Robi/Airtel number, or use the Unsubscribe form on this page. Upon unsubscription you will be automatically logged out of the app and returned to the login page.</p>

    <h3>6. Who handles my subscription?</h3>
    <p>Subscriptions are managed by BDApps. All charges appear on your mobile bill. For support, contact <a href="mailto:support@bdapps.com">support@bdapps.com</a> or call +8809610999922.</p>

    <h3>7. What does the subscription response message say?</h3>
    <p>It includes the <strong><?php echo htmlspecialchars($APP_CATEGORY); ?></strong> category and the official APK download link.</p>
  </div>
</div>

<!-- ===== Privacy Modal ===== -->
<div id="privacy" class="modal-backdrop" role="dialog" aria-modal="true" aria-labelledby="privacy-title">
  <div class="modal">
    <button class="modal-close" aria-label="Close" onclick="closeModal('privacy')">&times;</button>
    <h2 id="privacy-title">Privacy Notice</h2>
    <p class="modal-sub">Last updated: <?php echo date('F Y'); ?></p>

    <h3>What we collect</h3>
    <p>We collect only your verified mobile number (used for subscription &amp; login) and the meal / water data you log inside the app.</p>

    <h3>What we do not collect</h3>
    <p>We do not collect your contacts, location, photos, or any other personal data outside what you explicitly log.</p>

    <h3>How subscription data is handled</h3>
    <p>Subscription status is verified directly with BDApps using your subscriber ID. We never store your password, OTP, or billing details.</p>

    <h3>Contact</h3>
    <p>Privacy questions: <a href="mailto:support@bdapps.com">support@bdapps.com</a> · +8809610999922.</p>
  </div>
</div>
</body>
</html>
