import 'package:flutter/material.dart';

class CameraErrorWidget extends StatelessWidget {
  final IconData? icon;
  final String error;
  const CameraErrorWidget({super.key, required this.error, this.icon});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: MediaQuery.of(context).size.width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon ?? Icons.videocam_off_outlined,
              size: 42,
              color: Colors.red.withOpacity(0.87),
            ),
            const SizedBox(height: 12.0),
            Text(
              error,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall!.copyWith(
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context)
                      .textTheme
                      .bodySmall!
                      .color!
                      .withOpacity(0.87)),
            ),
          ],
        ),
      ),
    );
  }
}
