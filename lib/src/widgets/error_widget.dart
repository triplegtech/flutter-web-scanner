import 'package:flutter/material.dart';

class CameraErrorWidget extends StatelessWidget {
  final IconData? icon;
  final String error;
  final bool retryButton;
  final void Function()? retryCallback;
  const CameraErrorWidget({
    super.key,
    required this.error,
    this.icon,
    this.retryButton = false,
    this.retryCallback,
  });

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
            if (retryButton) ...[
              const SizedBox(
                height: 8.0,
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  )
                ),
                onPressed: retryCallback,
                child: const Text('Tentar Novamente'),
              ),
            ]
          ],
        ),
      ),
    );
  }
}
