import 'package:flutter/material.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  final List<Map<String, String>> _reports = [
    {
      'title': 'Poor Street Lighting',
      'location': 'Near Civil Lines Metro Station',
      'time': '2 hours ago',
      'type': 'Hazard',
      'severity': 'Medium',
    },
    {
      'title': 'Isolated Alley / High Risk',
      'location': 'Behind Sector 14 Commercial Complex',
      'time': '5 hours ago',
      'type': 'Unsafe Zone',
      'severity': 'High',
    },
    {
      'title': 'Police Patrolling Active',
      'location': 'University Main Gate Road',
      'time': '1 day ago',
      'type': 'Safe Note',
      'severity': 'Low',
    },
  ];

  final _titleController = TextEditingController();
  final _locationController = TextEditingController();

  void _showReportDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2C),
        title: const Text('Report Unsafe Area', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Issue / Report Title',
                labelStyle: TextStyle(color: Colors.white60),
                hintText: 'e.g. Unlit street, Suspicious activity',
                hintStyle: TextStyle(color: Colors.white24),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _locationController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Location / Landmark',
                labelStyle: TextStyle(color: Colors.white60),
                hintText: 'e.g. Near Bus Stand',
                hintStyle: TextStyle(color: Colors.white24),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              if (_titleController.text.isNotEmpty && _locationController.text.isNotEmpty) {
                setState(() {
                  _reports.insert(0, {
                    'title': _titleController.text.trim(),
                    'location': _locationController.text.trim(),
                    'time': 'Just now',
                    'type': 'User Report',
                    'severity': 'High',
                  });
                });
                _titleController.clear();
                _locationController.clear();
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('📢 Safety report posted to community map!'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: const Text('Post Report', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double bottomInset = MediaQuery.of(context).viewPadding.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFF12121A),
      appBar: AppBar(
        title: const Text('Community Safety Map'),
        backgroundColor: const Color(0xFF1E1E2C),
      ),
      body: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // HEADER BANNER
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orangeAccent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.orangeAccent.withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 30),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "Crowdsourced Community Watch: Stay informed about unsafe zones & reported hazards nearby.",
                      style: TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            const Text(
              "RECENT LOCAL SAFETY ALERTS",
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),

            const SizedBox(height: 12),

            Expanded(
              child: ListView.builder(
                itemCount: _reports.length,
                padding: EdgeInsets.only(bottom: bottomInset + 80), // space for FAB
                itemBuilder: (context, index) {
                  final report = _reports[index];
                  bool isHigh = report['severity'] == 'High';

                  return Card(
                    color: const Color(0xFF1E1E2C),
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: isHigh ? Colors.redAccent.withOpacity(0.5) : Colors.white10,
                      ),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isHigh
                            ? Colors.redAccent.withOpacity(0.2)
                            : Colors.orangeAccent.withOpacity(0.2),
                        child: Icon(
                          isHigh ? Icons.report_problem : Icons.info_outline,
                          color: isHigh ? Colors.redAccent : Colors.orangeAccent,
                        ),
                      ),
                      title: Text(
                        report['title']!,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        "${report['location']} • ${report['time']}",
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isHigh ? Colors.redAccent : Colors.orangeAccent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          report['severity']!,
                          style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: SafeArea(
        child: FloatingActionButton.extended(
          onPressed: _showReportDialog,
          backgroundColor: Colors.redAccent,
          icon: const Icon(Icons.add_location_alt, color: Colors.white),
          label: const Text(
            'Report Unsafe Area',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}