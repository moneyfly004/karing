import 'package:flutter/material.dart';
import 'package:karing/features/moneyfly/moneyfly_account_controller.dart';
import 'package:karing/features/moneyfly/moneyfly_auth_screen.dart';
import 'package:karing/screens/home_screen.dart';
import 'package:provider/provider.dart';

class MoneyflyAuthGate extends StatelessWidget {
  const MoneyflyAuthGate({super.key, required this.launchUrl});

  final String launchUrl;

  @override
  Widget build(BuildContext context) {
    return Consumer<MoneyflyAccountController>(
      builder: (context, account, _) {
        if (account.state == MoneyflySessionState.checking) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (!account.signedIn) {
          return const MoneyflyAuthScreen();
        }
        return HomeScreen(launchUrl: launchUrl);
      },
    );
  }
}
