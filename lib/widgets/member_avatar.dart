import 'package:flutter/material.dart';
import '../utils/constants.dart';
import '../utils/helpers.dart';

class MemberAvatar extends StatelessWidget {
  final String name;
  final String colorHex;
  final double size;
  final double fontSize;
  final bool showBorder;

  const MemberAvatar({
    super.key,
    required this.name,
    required this.colorHex,
    this.size = 40,
    this.fontSize = 14,
    this.showBorder = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppConstants.colorFromHex(colorHex);
    final initials = Helpers.getInitials(name);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: showBorder
            ? Border.all(color: Colors.white, width: 2)
            : null,
        boxShadow: [
          BoxShadow(
            color: color.withAlpha(80),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class MemberAvatarStack extends StatelessWidget {
  final List<({String name, String colorHex})> members;
  final double size;
  final int maxShown;

  const MemberAvatarStack({
    super.key,
    required this.members,
    this.size = 32,
    this.maxShown = 4,
  });

  @override
  Widget build(BuildContext context) {
    final shown = members.take(maxShown).toList();
    final extra = members.length - shown.length;

    return SizedBox(
      height: size,
      width: shown.length * (size * 0.65) + (extra > 0 ? size * 0.65 : 0),
      child: Stack(
        children: [
          ...shown.asMap().entries.map((entry) {
            return Positioned(
              left: entry.key * (size * 0.65),
              child: MemberAvatar(
                name: entry.value.name,
                colorHex: entry.value.colorHex,
                size: size,
                fontSize: size * 0.35,
                showBorder: true,
              ),
            );
          }),
          if (extra > 0)
            Positioned(
              left: shown.length * (size * 0.65),
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Center(
                  child: Text(
                    '+$extra',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: size * 0.32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

