import 'package:flutter/material.dart';

class CompositionTechnique {
  final String title;
  final String category;
  final String labelText;
  final String detailText;
  final String imageAsset;

  const CompositionTechnique({
    required this.title,
    required this.category,
    required this.labelText,
    required this.detailText,
    required this.imageAsset,
  });
}

class CompositionLibraryScreen extends StatelessWidget {
  const CompositionLibraryScreen({super.key});

  static const categories = <String>[
    '全部',
    '日常人像 (Portrait)',
    '美食靜物 (Food)',
    '風景建築 (Landscape)',
  ];

  static const techniques = <CompositionTechnique>[
    CompositionTechnique(
      title: '三分法構圖',
      category: 'Portrait',
      labelText: '三分線交點',
      detailText: '將主體置於 3x3 交點處，畫面更穩定有張力。交點位置能自然引導視線，保持畫面平衡，同時加強構圖節奏。',
      imageAsset: 'assets/library/portrait/portrait-rule of third.jpg',
    ),
    CompositionTechnique(
      title: '留白構圖',
      category: 'Portrait',
      labelText: '留白突出',
      detailText: '利用留白空間讓人物主體更清晰、視線更聚焦。適當的空間感也能營造簡約美感，增強照片的故事性與氛圍。',
      imageAsset: 'assets/library/portrait/negative space.jpg',
    ),
    CompositionTechnique(
      title: '框架構圖',
      category: 'Portrait',
      labelText: '自然框架',
      detailText: '用窗框、樹枝或門框構成自然畫框，突顯人物。框架邊緣會引導觀眾視線並加強畫面的深度層次。',
      imageAsset: 'assets/library/portrait/framing.jpg',
    ),
    CompositionTechnique(
      title: '鳥瞰圖',
      category: 'Food',
      labelText: '俯視擺盤',
      detailText: '從上方俯視拍攝，呈現食物排列與紋理細節。讓擺盤構成主視覺，視覺重心自然落在中央主題，畫面更整潔有序。',
      imageAsset: 'assets/library/food/Food flat lay.jpg',
    ),
    CompositionTechnique(
      title: '中心構圖',
      category: 'Food',
      labelText: '餐點中心',
      detailText: '把餐點放在畫面中心，讓視線立刻鎖定主題。對稱構圖可以增加穩定感，讓作品更適合特寫與產品宣傳。',
      imageAsset: 'assets/library/food/Centered food photography.jpg',
    ),
    CompositionTechnique(
      title: '對角線構圖',
      category: 'Food',
      labelText: '對角線節奏',
      detailText: '沿對角線排布元素，讓畫面更具動感和延伸感。對角線的引導效果能讓視線穿過畫面，增強整體節奏感。',
      imageAsset: 'assets/library/food/Diagonal food photography.jpg',
    ),
    CompositionTechnique(
      title: '三分法構圖',
      category: 'Landscape',
      labelText: '地平三分',
      detailText: '地平線與主題依三分法安排，畫面平衡又舒適。前景與遠景的層次更明確，能帶出更強的空間感與視覺節奏。',
      imageAsset: 'assets/library/landscape/landscape-rule of third.jpg',
    ),
    CompositionTechnique(
      title: '對稱構圖',
      category: 'Landscape',
      labelText: '對稱穩定',
      detailText: '用左右或上下對稱的建築與景物營造寧靜穩定感。這種構圖特別適合極簡風景與建築拍攝，表現出和諧與秩序。',
      imageAsset: 'assets/library/landscape/symmetry.jpg',
    ),
    CompositionTechnique(
      title: '引導線構圖',
      category: 'Landscape',
      labelText: '引導視線',
      detailText: '讓道路、欄杆或建築線條引導觀眾視線。引導線會帶出深度和方向感，讓觀者自然走入畫面並停留在主題上。',
      imageAsset: 'assets/library/landscape/guide method.jpg',
    ),
  ];

  void _openTechniqueDetail(BuildContext context, List<CompositionTechnique> items, int startIndex) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => CompositionDetailScreen(
          items: items,
          initialIndex: startIndex,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: categories.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('構圖法庫'),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                '返回主畫面',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            indicatorColor: const Color(0xFF0A58F5),
            tabs: categories.map((category) {
              return Tab(text: category);
            }).toList(),
          ),
        ),
        body: TabBarView(
          children: categories.map((category) {
            final filterKey = category == '日常人像 (Portrait)'
                ? 'Portrait'
                : category == '美食靜物 (Food)'
                    ? 'Food'
                    : category == '風景建築 (Landscape)'
                        ? 'Landscape'
                        : null;
            final items = filterKey == null
                ? techniques
                : techniques.where((technique) => technique.category == filterKey).toList();
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: GridView.builder(
                physics: const BouncingScrollPhysics(),
                itemCount: items.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.76,
                ),
                itemBuilder: (context, index) {
                  final technique = items[index];
                  return CompositionCard(
                    technique: technique,
                    onTap: () => _openTechniqueDetail(context, items, index),
                  );
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class CompositionCard extends StatelessWidget {
  final CompositionTechnique technique;
  final VoidCallback? onTap;

  const CompositionCard({super.key, required this.technique, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1B1B1F),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                child: Image.asset(
                  technique.imageAsset,
                  fit: BoxFit.cover,
                  cacheWidth: 400,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: const Color(0xFF2A2A2A),
                      child: Center(
                        child: Icon(
                          technique.category == 'Portrait'
                              ? Icons.person_outline
                              : technique.category == 'Food'
                                  ? Icons.fastfood
                                  : Icons.landscape,
                          color: Colors.white30,
                          size: 44,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    technique.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    technique.labelText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFB0B8C1),
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CompositionDetailScreen extends StatefulWidget {
  final List<CompositionTechnique> items;
  final int initialIndex;

  const CompositionDetailScreen({super.key, required this.items, required this.initialIndex});

  @override
  State<CompositionDetailScreen> createState() => _CompositionDetailScreenState();
}

class _CompositionDetailScreenState extends State<CompositionDetailScreen> {
  late int currentIndex;
  int selectedRating = 0;
  bool showText = true;

  @override
  void initState() {
    super.initState();
    currentIndex = widget.initialIndex;
  }

  void _showPrevious() {
    if (currentIndex > 0) {
      setState(() {
        currentIndex -= 1;
      });
    }
  }

  void _showNext() {
    if (currentIndex < widget.items.length - 1) {
      setState(() {
        currentIndex += 1;
      });
    }
  }

  void _rate(int rating) {
    setState(() {
      selectedRating = rating;
    });
  }

  @override
  Widget build(BuildContext context) {
    final technique = widget.items[currentIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          technique.title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.asset(
                  technique.imageAsset,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  cacheWidth: 1080,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: const Color(0xFF2A2A2A),
                      child: const Center(
                        child: Icon(
                          Icons.broken_image,
                          color: Colors.white30,
                          size: 56,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (showText)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xCC4A4A4A),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                technique.detailText,
                style: const TextStyle(color: Colors.white, fontSize: 18, height: 1.5),
              ),
            ),
          const SizedBox(height: 16),
        ],
      ),
      bottomNavigationBar: Container(
        color: const Color(0xFF121212),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Container(
          height: 72,
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E22),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: const Color(0xFF2A2A2A)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Center(
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: IconButton(
                      onPressed: currentIndex > 0 ? _showPrevious : null,
                      icon: const Icon(Icons.arrow_back_ios),
                      color: currentIndex > 0 ? Colors.white : Colors.white38,
                      iconSize: 28,
                      splashRadius: 28,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: IconButton(
                      onPressed: () => setState(() {
                        showText = !showText;
                      }),
                      icon: Icon(showText ? Icons.visibility_off : Icons.visibility),
                      color: Colors.white,
                      iconSize: 28,
                      splashRadius: 28,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: IconButton(
                      onPressed: currentIndex < widget.items.length - 1 ? _showNext : null,
                      icon: const Icon(Icons.arrow_forward_ios),
                      color: currentIndex < widget.items.length - 1 ? Colors.white : Colors.white38,
                      iconSize: 28,
                      splashRadius: 28,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
