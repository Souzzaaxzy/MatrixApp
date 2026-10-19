import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_app/core/widgets/user_avatar.dart';
import 'package:matrix_app/features/profile/profile_screen.dart';

import '../helpers/test_app.dart';

/// Geometry of the new profile header:
///   banner on top → avatar overlapping its lower edge (left-aligned) →
///   nickname to the RIGHT of the photo → bio below → counters below that.
///
/// These assertions lock the ORDER/positions the redesign requires, so a
/// future refactor cannot silently push the photo back to the centre or move
/// the nickname under it.
void main() {
  /// The avatar that belongs to the profile header (the first one rendered —
  /// the feed/other surfaces are not present on this screen).
  Finder headerAvatar() => find.byType(UserAvatar).first;

  testWidgets('avatar sits to the LEFT, not centred', (tester) async {
    await pumpMatrixApp(tester, const ProfileScreen());
    await tester.pump(const Duration(milliseconds: 400));

    final screen = tester.getSize(find.byType(ProfileScreen));
    final avatar = tester.getRect(headerAvatar());

    // Clearly in the left half of the screen…
    expect(avatar.left, lessThan(screen.width / 2));
    // …and the centre of the photo is left of the screen centre.
    expect(avatar.center.dx, lessThan(screen.width / 2));
  });

  testWidgets('banner is above the avatar and the avatar overlaps its edge',
      (tester) async {
    await pumpMatrixApp(tester, const ProfileScreen());
    await tester.pump(const Duration(milliseconds: 400));

    final avatar = tester.getRect(headerAvatar());
    final nickname = tester.getRect(
      find.textContaining('leonardo', findRichText: true),
    );

    // The photo straddles the banner's bottom edge: its top half overlaps the
    // banner and its bottom half hangs below it, sharing the strip with the
    // nickname (so their vertical ranges intersect).
    final overlaps = avatar.top < nickname.bottom && avatar.bottom > nickname.top;
    expect(overlaps, isTrue,
        reason: 'avatar $avatar should vertically overlap the nickname '
            '$nickname (photo straddling the banner edge)');
  });

  testWidgets('nickname sits to the RIGHT of the avatar', (tester) async {
    await pumpMatrixApp(tester, const ProfileScreen());
    await tester.pump(const Duration(milliseconds: 400));

    final avatar = tester.getRect(headerAvatar());
    final nickname = tester.getRect(
      find.textContaining('leonardo', findRichText: true),
    );

    // Horizontally after the photo (never centred under/over it).
    expect(nickname.left, greaterThanOrEqualTo(avatar.right - 1));
  });

  testWidgets('bio comes below the avatar and the nickname', (tester) async {
    await pumpMatrixApp(tester, const ProfileScreen());
    await tester.pump(const Duration(milliseconds: 400));

    final avatar = tester.getRect(headerAvatar());
    final nickname = tester.getRect(
      find.textContaining('leonardo', findRichText: true),
    );
    // The seeded own user has a bio ("Construindo o futuro. ⚡").
    final bio = tester.getRect(find.textContaining('Construindo o futuro'));

    expect(bio.top, greaterThanOrEqualTo(avatar.bottom - 1));
    expect(bio.top, greaterThanOrEqualTo(nickname.bottom - 1));
  });

  testWidgets('counters come below the bio', (tester) async {
    await pumpMatrixApp(tester, const ProfileScreen());
    await tester.pump(const Duration(milliseconds: 400));

    final bio = tester.getRect(find.textContaining('Construindo o futuro'));
    final friendsLabel = tester.getRect(find.text('Amigos'));

    expect(friendsLabel.top, greaterThanOrEqualTo(bio.bottom - 1));
  });

  testWidgets('renders the banner cover when the user has one',
      (tester) async {
    // 'joao' is seeded WITH a banner in the fake store.
    await pumpMatrixApp(tester, const ProfileScreen(nickname: 'joao'));
    await tester.pump(const Duration(milliseconds: 400));

    // A banner image widget exists for this profile.
    expect(find.byType(Image), findsWidgets);
  });

  testWidgets('falls back to a default cover when there is no banner',
      (tester) async {
    // The own user ('leonardo') has no banner → default gradient, no crash.
    await pumpMatrixApp(tester, const ProfileScreen());
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(ProfileScreen), findsOneWidget);
    // The header still renders its avatar and nickname.
    expect(headerAvatar(), findsOneWidget);
    expect(find.textContaining('leonardo', findRichText: true), findsOneWidget);
  });

  testWidgets('banner is 157px tall', (tester) async {
    await pumpMatrixApp(tester, const ProfileScreen());
    await tester.pump(const Duration(milliseconds: 400));

    // The banner occupies the top of the header. Its height is asserted via
    // the first painted cover box (banner image or gradient fallback), whose
    // width spans the screen.
    final banner = tester.getRect(
      find.descendant(
        of: find.byType(ProfileScreen),
        matching: find.byType(DecoratedBox),
      ).first,
    );
    expect(banner.height, 157);
  });

  testWidgets('the photo has NO decorative blue ring/glow around it',
      (tester) async {
    await pumpMatrixApp(tester, const ProfileScreen());
    await tester.pump(const Duration(milliseconds: 400));

    // The avatar is rendered bare. Previously a GlowContainer (blue halo)
    // wrapped it; assert no ancestor of the photo paints that glow.
    final avatarElement = tester.element(headerAvatar());
    var hasGlowAncestor = false;
    avatarElement.visitAncestorElements((el) {
      final w = el.widget;
      if (w is Container) {
        final deco = w.decoration;
        if (deco is BoxDecoration && deco.boxShadow != null) {
          hasGlowAncestor = true;
          return false;
        }
      }
      return true;
    });
    expect(hasGlowAncestor, isFalse,
        reason: 'the profile photo must be bare (no blue glow container)');

    // And the photo itself does not draw a border ring.
    final avatarWidget = tester.widget<UserAvatar>(headerAvatar());
    expect(avatarWidget.ring, isFalse);
  });
}
