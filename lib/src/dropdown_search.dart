import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'suggestions_box_controller.dart';

typedef OptionsInputSuggestions<T> = FutureOr<List<T>> Function(String query);
typedef OptionSelected<T> = void Function(T data, bool selected);
typedef OptionsBuilder<T> = Widget Function(
    BuildContext context, OptionsInputState<T> state, T data);

class OptionsInput<T> extends StatefulWidget {
  final OptionsInputSuggestions<T> findSuggestions;
  final ValueChanged<T> onChanged;
  final OptionsBuilder<T> suggestionBuilder;
  final TextEditingController? textEditingController;
  final double suggestionsBoxMaxHeight;
  final double inputHeight;
  final double spaceSuggestionBox;
  final FocusNode? focusNode;
  final InputDecoration? inputDecoration;
  final TextInputAction? textInputAction;
  final TextStyle? textStyle;
  final double scrollPadding;
  final List<T> initOptions;
  final double borderRadius;
  final Color backgroundColor;
  final bool enabled;
  final Function? onTextChanged;
  final int maxLength;
  final TextInputType keyboardType;
  final TextCapitalization textCapitalization;

  const OptionsInput(
      {Key? key,
      required this.findSuggestions,
      required this.onChanged,
      required this.suggestionBuilder,
      this.textEditingController,
      this.focusNode,
      this.inputDecoration,
      this.textInputAction,
      this.textStyle,
      this.suggestionsBoxMaxHeight = 0,
      this.scrollPadding = 40,
      this.initOptions = const [],
      this.inputHeight = 40,
      this.spaceSuggestionBox = 4,
      this.borderRadius = 0,
      this.backgroundColor = Colors.white,
      this.enabled = true,
      this.onTextChanged,
      this.maxLength = 50,
      this.keyboardType = TextInputType.text,
      this.textCapitalization = TextCapitalization.sentences})
      : super(key: key);

  @override
  OptionsInputState<T> createState() => OptionsInputState<T>();
}

class OptionsInputState<T> extends State<OptionsInput<T>> {
  final _layerLink = LayerLink();
  final _suggestionsStreamController = StreamController<List<T>?>.broadcast();
  int _searchId = 0;
  late SuggestionsBoxController _suggestionsBoxController;
  late FocusNode _focusNode;

  RenderBox get renderBox => context.findRenderObject() as RenderBox ;

  @override
  void initState() {
    super.initState();
    _suggestionsBoxController = SuggestionsBoxController(context);
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_handleFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _initOverlayEntry();
    });
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (SizeChangedLayoutNotification val) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          _suggestionsBoxController.overlayEntry?.markNeedsBuild();
        });
        return true;
      },
      child: SizeChangedLayoutNotifier(
        child: Column(
          children: [
            Container(
              child: TextField(
                textCapitalization: widget.textCapitalization,
                controller: widget.textEditingController,
                focusNode: _focusNode,
                onChanged: (val) {
                  _onSearchChanged(val);
                  widget.onTextChanged?.call(val);
                },
                decoration: widget.inputDecoration?.copyWith(counterText: ''),
                textInputAction: widget.textInputAction,
                maxLines: 1,
                style: widget.textStyle,
                onSubmitted: _onSearchChanged,
                scrollPadding: EdgeInsets.only(bottom: widget.scrollPadding),
                enabled: widget.enabled,
                maxLength: widget.maxLength,
                keyboardType: widget.keyboardType,
              ),
              height: widget.inputHeight,
            ),
            CompositedTransformTarget(
              link: _layerLink,
              child: Container(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    if (null == widget.focusNode) {
      _focusNode.dispose();
    }
    _suggestionsStreamController.close();
    _suggestionsBoxController.close();
    super.dispose();
  }

  void _initOverlayEntry() {
    _suggestionsBoxController.overlayEntry = OverlayEntry(
      builder: (context) {
        final size = renderBox.size;
        final renderBoxOffset = renderBox.localToGlobal(Offset.zero);
        final topAvailableSpace = renderBoxOffset.dy;
        final mq = MediaQuery.of(context);
        final bottomAvailableSpace =
            mq.size.height - mq.viewInsets.bottom - renderBoxOffset.dy - size.height;
        final showTop = topAvailableSpace > bottomAvailableSpace;
        final _suggestionBoxHeight = showTop
            ? min(topAvailableSpace, widget.suggestionsBoxMaxHeight)
            : min(bottomAvailableSpace, widget.suggestionsBoxMaxHeight);

        final compositedTransformFollowerOffset = showTop
            ? Offset(0, -size.height - widget.spaceSuggestionBox)
            : Offset(0, widget.spaceSuggestionBox);

        return StreamBuilder<List<T>?>(
          stream: _suggestionsStreamController.stream,
          builder: (context, snapshot) {
            if (snapshot.hasData && (snapshot.data?.isNotEmpty??false)) {
              var suggestionsListView = Material(
                elevation: 4.0,
                borderRadius: BorderRadius.circular(widget.borderRadius),
                color: widget.backgroundColor,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: _suggestionBoxHeight,
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: snapshot.data?.length,
                    itemBuilder: (BuildContext context, int index) {
                      return widget.suggestionBuilder(context, this, snapshot.data![index]);
                    },
                  ),
                ),
              );
              return Positioned(
                width: size.width,
                child: CompositedTransformFollower(
                  link: _layerLink,
                  showWhenUnlinked: false,
                  offset: compositedTransformFollowerOffset,
                  child: !showTop
                      ? suggestionsListView
                      : FractionalTranslation(
                          translation: const Offset(0, -1),
                          child: suggestionsListView,
                        ),
                ),
              );
            }
            return Container();
          },
        );
      },
    );
  }

  void selectSuggestion(T data) {
    _suggestionsStreamController.add(null);
    widget.onChanged(data);
  }

  void _onSearchChanged(String value) async {
    final localId = ++_searchId;
    final results = await widget.findSuggestions(value);
    if (_searchId == localId && mounted) {
      _suggestionsStreamController.add(results);
    }
  }

  void _handleFocusChanged() {
    if (_focusNode.hasFocus) {
      _suggestionsBoxController.open();
      Future.delayed(Duration(milliseconds: 100))
          .then((value) => _suggestionsStreamController.add(widget.initOptions));
    } else {
      _suggestionsBoxController.close();
    }
  }

  void forceShow(bool isShow) {
    _suggestionsStreamController.add(isShow ? widget.initOptions : null);
  }

  void showSuggestions(List<T> items) {
    _suggestionsStreamController.add(items);
  }
}
