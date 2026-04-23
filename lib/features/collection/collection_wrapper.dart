import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'collection_screen.dart';
import '../wantlist/wantlist_screen.dart';

class CollectionWrapper extends StatefulWidget {
  const CollectionWrapper({super.key});

  @override
  State<CollectionWrapper> createState() => _CollectionWrapperState();
}

class _CollectionWrapperState extends State<CollectionWrapper>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpinnerTheme.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: SpinnerTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TabBar(
                  controller: _tabController,
                  labelColor: SpinnerTheme.white,
                  unselectedLabelColor: SpinnerTheme.grey,
                  labelStyle: SpinnerTheme.nunito(
                      size: 14, weight: FontWeight.w700),
                  unselectedLabelStyle: SpinnerTheme.nunito(
                      size: 14, weight: FontWeight.w500),
                  indicator: BoxDecoration(
                    color: SpinnerTheme.accent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  tabs: const [
                    Tab(text: 'Collection'),
                    Tab(text: 'Wantlist'),
                  ],
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [
                  CollectionScreen(),
                  WantlistScreen(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
