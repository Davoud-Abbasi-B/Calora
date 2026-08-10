import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/activation_provider.dart';

class ActivationScreen extends ConsumerStatefulWidget {
  const ActivationScreen({super.key});

  @override
  ConsumerState<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends ConsumerState<ActivationScreen> {
  final _usernameController = TextEditingController();

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _submit() =>
      ref.read(activationProvider.notifier).activate(_usernameController.text);

  @override
  Widget build(BuildContext context) {
    final activation = ref.watch(activationProvider);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    label: 'نشان Calora',
                    image: true,
                    child: SizedBox(
                      height: 150,
                      child: Image.asset(
                        'assets/logo/app_logo.png',
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'فعال‌سازی Calora',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'برای استفاده از برنامه، نام کاربری فعال‌سازی را وارد کنید.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _usernameController,
                    enabled: !activation.isSubmitting,
                    textDirection: TextDirection.ltr,
                    textInputAction: TextInputAction.done,
                    autocorrect: false,
                    enableSuggestions: false,
                    autofillHints: const [AutofillHints.username],
                    decoration: InputDecoration(
                      labelText: 'نام کاربری',
                      errorText: activation.errorMessage,
                      prefixIcon: const Icon(Icons.person_outline_rounded),
                    ),
                    onSubmitted: activation.isSubmitting
                        ? null
                        : (_) => _submit(),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: activation.isSubmitting ? null : _submit,
                    child: activation.isSubmitting
                        ? const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text('فعال‌سازی'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
