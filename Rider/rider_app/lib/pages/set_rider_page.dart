import 'package:flutter/material.dart';
import '../services/api_service.dart';

class SetRiderPage extends StatelessWidget {
  const SetRiderPage({super.key});

  Future<void> _submitRiderData() async {
    Map<String, dynamic> riderData = {
      "id": "rider101",
      "name": "Ravi",
      "start": [12.9716, 77.5946],
      "end": [12.9352, 77.6148],
      "route": [
        [12.9716, 77.5946],
        [12.9600, 77.5950],
        [12.9450, 77.6000],
        [12.9352, 77.6148]
      ],
      "preferences": {
        "gender": "any",
        "smoking": "no",
        "pets": "yes"
      }
    };

    final result = await ApiService.setRiderRoute(riderData);
    print(result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Set Rider Route")),
      body: Center(
        child: ElevatedButton(
          onPressed: _submitRiderData,
          child: const Text("Submit Rider Info"),
        ),
      ),
    );
  }
}
