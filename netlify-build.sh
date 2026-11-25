#!/usr/bin/env bash
# Netlify's build of the web version (see netlify.toml). Its build image has
# no Flutter: the exact version used on the developer's PC is fetched — a
# shallow clone of its tag, far lighter than the 1.5 GB archive — then the
# app is built into build/web.
set -euo pipefail
: "${FLUTTER_VERSION:?}" "${SUPABASE_URL:?}" "${SUPABASE_ANON_KEY:?}"

FLUTTER_DIR="$HOME/flutter-$FLUTTER_VERSION"
if [ ! -x "$FLUTTER_DIR/bin/flutter" ]; then
  git clone --quiet --depth 1 --branch "$FLUTTER_VERSION" \
    https://github.com/flutter/flutter.git "$FLUTTER_DIR"
fi
export PATH="$FLUTTER_DIR/bin:$PATH"

flutter --disable-analytics > /dev/null 2>&1 || true
flutter --version
# exactly the versions in pubspec.lock (the ones that work on the PC):
# a mismatch fails here instead of picking newer, untested versions
flutter pub get --enforce-lockfile
flutter build web --release \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"

# the cache rules travel with the site
test -f build/web/_headers
echo "Web build ready in build/web"
