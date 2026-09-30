CARA DJ FOR IPHONE (native app, built from your Windows PC)
===========================================================
What this is: a real iPhone app version of your DJ. Unlike the Safari page it can
  - keep running with the screen locked,
  - make iOS turn the Spotify app DOWN while Cara talks (real ducking),
  - use your stingers, DJ mood, song trivia, and the queue buttons.
It plays through the Spotify app (you start a playlist there, like on the PC app).

HOW IT GETS TO YOUR PHONE
  Your PC can't compile iPhone apps, so GitHub's free cloud Macs do it. Then a free Windows tool
  (Sideloadly) installs the result on your iPhone. You never need a Mac.

STEP 1: Put the code on GitHub  (about 5 minutes)
  a) Sign in to github.com > New repository. Name it  cara-dj-ios . Choose PUBLIC (public repos get
     free cloud-Mac time). Create it.
  b) On the repo page click "uploading an existing file". Open this CaraDJ-iOS folder and drag in:
        project.yml, .gitignore, the CaraDJ folder, and the Support folder.
     (If your browser won't drag folders, upload with GitHub Desktop or "git push" instead.)
     Click Commit changes.
  c) Add the build recipe: Add file > Create new file. In the name box type exactly
        .github/workflows/build.yml
     (typing the slashes makes the folders). Open the file  build.yml  from this folder's
     .github/workflows, copy ALL its text, paste it in, and Commit.

STEP 2: Let GitHub build it  (5 to 10 minutes)
  Open the repo's Actions tab. A run called "Build Cara DJ" starts by itself. Wait for the green check.
  Click the run, scroll to Artifacts, click  CaraDJ-ipa  to download. Unzip it: inside is CaraDJ.ipa.
  If the run turns red, open it, copy the red error text, and send it to Claude. This is the most
  likely place for a first-try hiccup, and each one is a quick fix.

STEP 3: Put it on your iPhone with Sideloadly
  a) Install iTunes and iCloud from apple.com (the direct downloads, NOT the Microsoft Store ones), then
     Sideloadly from sideloadly.io.
  b) Plug in your iPhone, tap Trust. Open Sideloadly, drag CaraDJ.ipa in, type your Apple ID, Start.
  c) On the iPhone: Settings > General > VPN & Device Management > your Apple ID > Trust.
     Then Settings > Privacy & Security > Developer Mode > On (the phone restarts).
  With a free Apple ID the app stops opening after 7 days. Just run Sideloadly again to renew it.
  (A paid $99/year Apple developer account makes it last a year.)

STEP 4: Tell Spotify about the app
  developer.spotify.com/dashboard > your app > Settings > Redirect URIs > add exactly:
        caradj://callback
  Save. Use the same Client ID you used before.

STEP 5: First run
  Open Cara DJ > SETTINGS. Paste your Spotify Client ID, ElevenLabs key (sk_...) and Voice ID, Gemini key,
  and town. Tap Connect Spotify and Agree. In the Spotify app start your playlist, come back, tap
  START DJ, then you can lock the phone.

THINGS I COULDN'T TEST (I can't run iPhone apps), so tell me what happens
  - Does Spotify get turned down while Cara talks, and come back up after?
  - Does it keep working with the screen locked for a whole playlist?
  - The SILENT transition pauses Spotify through its API; if the music doesn't resume, tell me.
  - The stingers (SILENT only) and the volume sliders.
  - Breaking news and fade-out aren't in this first version. Music-under-DJ level is set by iOS
    (no slider).
