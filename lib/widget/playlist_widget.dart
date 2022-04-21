// ignore_for_file: constant_identifier_names, curly_braces_in_flow_control_structures

import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:ztv/model/playlist.dart';

import '../util/util.dart';
import 'channel.dart';

class PlaylistWidget extends StatefulWidget {
  var _linkOrList;

  final onTap;

  final _offset;

  String? _query;
  var _filterLanguage;
  var _filterCategory;
  final _txtFieldTxt;
  List<String> _dropDownLanguages;
  List<String> _dropDownCategories;
  var hasFilter;
  var hasSavePlayList;
  final _xLink;

  PlaylistWidget(this._linkOrList, this._xLink, this.onTap, this._offset, this._query, this._filterLanguage, this._filterCategory,
      this._txtFieldTxt, this._dropDownLanguages, this._dropDownCategories, this.hasFilter, this.hasSavePlayList);

  @override
  State<StatefulWidget> createState() => _PlaylistWidgetState();
}

class _PlaylistWidgetState extends State<PlaylistWidget> {
  static const TAG = '_PlaylistState';
  late ScrollController _scrollController;
  var showSearchView = false;
  var ctr;
  bool linkBroken = false;

  @override
  void initState() {
    _scrollController = ScrollController(initialScrollOffset: widget._offset);
    ctr = TextEditingController(text: widget._query);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    var searchActive = showSearchView || (widget._query != null && widget._query?.isNotEmpty == true);
    return Scaffold(
      appBar: AppBar(leading: BackButton(), actions: [
        const SizedBox(width: 48),
        Expanded(
            child: searchActive
                ? TextField(
                    style: TextStyle(color: Colors.white),
                    onChanged: (String txt) {
                      if (txt.trim().isNotEmpty)
                        setState(() {
                          widget._query = txt;
                        });
                    },
                    controller: ctr,
                    cursorColor: Colors.white,
                    // controller: TextEditingController(text: widget._query),
                    decoration: InputDecoration(
                        contentPadding: const EdgeInsets.only(top: 16),
                        focusedBorder: UnderlineInputBorder(borderSide: const BorderSide(color: Colors.white))),
                  )
                : Container()),
        searchActive
            ? IconButton(
                icon: Icon(
                  Icons.close,
                  color: Colors.white,
                ),
                onPressed: () => setState(() {
                  showSearchView = false;
                  widget._query = null;
                  ctr = null;
                }),
              )
            : IconButton(
                icon: Icon(
                  Icons.search,
                  color: Colors.white,
                ),
                onPressed: () => setState(() => showSearchView = true)),
        widget.hasFilter
            ? IconButton(
                icon: Icon(Icons.filter_list, color: Colors.white),
                onPressed: () => dialog(
                        context,
                        (lan, cat) => setState(() {
                              widget._filterLanguage = lan;
                              widget._filterCategory = cat;
                              log(TAG, "submit lan=>$lan; cat=>$cat");
                            }), () {
                      widget._filterLanguage = getLocalizedLanguage(ANY_LANGUAGE, context);
                      widget._filterCategory = getLocalizedCategory(ANY_CATEGORY, context);
                    }))
            : SizedBox.shrink(),
        if (widget.hasSavePlayList)
          IconButton(
              icon: Icon(Icons.save, color: Colors.white),
              onPressed: () => showDialog(context: context, builder: (_) => SaveDialog(widget._txtFieldTxt)))
      ]),
      body: FutureBuilder(
        future: (widget._query == null || widget._query?.isEmpty == true) &&
                (widget._filterLanguage == null || widget._filterLanguage == getLocalizedLanguage(ANY_LANGUAGE, context)) &&
                (widget._filterCategory == null || widget._filterCategory == getLocalizedCategory(ANY_CATEGORY, context))
            ? getChannels(widget._linkOrList, widget._xLink)
            : getFilteredChannels(getChannels(widget._linkOrList, widget._xLink), widget._query ?? ''),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return linkBroken
                ? Center(
                    child: Text(AppLocalizations.of(context)?.broken_link ?? 'Link is broken!', style: TextStyle(fontSize: 25)))
                : GridView.count(
                    crossAxisCount: MediaQuery.of(context).size.width >= 834 ? 4 : 3,
                    children: snapshot.data as List<Widget>,
                    controller: _scrollController,
                  );
          } else {
            return Center(child: CircularProgressIndicator());
          }
        },
      ),
    );
  }

  Future<List<Channel>> getChannels(link, xLink) {
    log(TAG, 'getChannels');
    if (link is List<Channel>) {
      log(TAG, 'link is list');
      link.forEach((ch) {
        if (ch.isOff) {
          link.remove(ch);
        } else {
          ch.filterLanguage = widget._filterLanguage;
          ch.filterCategory = widget._filterCategory;
          ch.sc = _scrollController;
        }
      });
      return Future.value(link);
    } else if (link.startsWith('/')) {
      return Future.value(fileToPlaylist(link));
    }
    return http.get(Uri.parse(widget._linkOrList)).then((value) async {
      if (value.statusCode == 404) {
        linkBroken = true;
        return Future.value(null);
      }
      const utf8decoder = Utf8Decoder();
      var data = utf8decoder.convert(value.bodyBytes);
      if (xLink != null) {
        final xData = await http.get(Uri.parse(xLink));
        data += utf8decoder.convert(xData.bodyBytes);
      }
      return parse(data);
    }, onError: (err) {
      linkBroken = true;
      Future.value(null);
    });
  }

  Future<List<Channel>> fileToPlaylist(link) => File(link).readAsString().then((value) => parse(value));

  Future<List<Channel>> parse(String data) async {
    log(TAG, 'parse');
    final lines = data.split("\n");
    final list = <Channel>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.startsWith('#EXTINF')) {
        final split = line.split(',');
        var title = split.last.replaceAll('====', '');
        String link = lines[++i];
        var endsWith = link.trim().endsWith('.png');
        if (endsWith) continue;
        String? category;
        if (link.startsWith('#EXTGRP')) {
          category = link.split(':')[1];
          i++;
        }
        while (!(link = lines[i]).startsWith('http')) i++;
        final channel = Channel(
            title,
            link,
            (String url, offset, query, language, category) => widget.onTap(url, list, offset, query, language, category, title,
                widget._dropDownLanguages, widget._dropDownCategories, widget.hasFilter));
        channel.sc = _scrollController;
        if (category != null) channel.categories.add(getLocalizedCategory(category, context));
        if (title.contains(RegExp('FRANCE|\\|FR\\|'))) {
          channel.languages.add(getLocalizedLanguage(FRENCH, context));
        } else if (title.contains(RegExp('\\|AR\\|'))) {
          channel.languages.add(getLocalizedLanguage(ARABIC, context));
        } else if (title.contains(RegExp('USA|5USA'))) {
          channel.languages.add(getLocalizedLanguage(ENGLISH, context));
        } else if (title.contains('NL')) {
          channel.languages.add(getLocalizedLanguage(DUTCH, context));
        } else if (link.contains(RegExp('latino|\\|SP\\|'))) {
          channel.languages.add(getLocalizedLanguage(SPANISH, context));
        } else if (title.contains(':')) {
          switch (title.split(':').first) {
            case 'FR':
              channel.languages.add(getLocalizedLanguage(FRENCH, context));
              break;
            case 'TR':
              channel.languages.add(getLocalizedLanguage(TURKISH, context));
              break;
          }
        }
        if (title.contains(RegExp('SPORTS?'))) {
          channel.categories.add(getLocalizedCategory(SPORTS, context));
        } else if (title.contains('News')) {
          channel.categories.add(getLocalizedCategory(NEWS, context));
        } else if (title.contains(RegExp('XXX|Brazzers'))) {
          channel.categories.add(XXX);
        } else if (title.contains(RegExp('BABY|CARTOON|JEUNESSE'))) {
          channel.categories.add(getLocalizedCategory(KIDS, context));
        } else if (title.contains(RegExp('MTV|Music'))) {
          channel.categories.add(getLocalizedCategory(MUSIC, context));
        }
        if (title.toLowerCase().contains('weather')) {
          channel.categories.add(getLocalizedCategory(WEATHER, context));
        }
        var data = split.first;
        setChannelProperties(data, channel);
        for (final l in channel.languages) {
          if (!widget._dropDownLanguages.contains(l)) widget._dropDownLanguages.add(l);
        }
        for (final c in channel.categories) {
          if (!widget._dropDownCategories.contains(c)) widget._dropDownCategories.add(c);
        }
        list.add(channel);
      }
    }
    log(TAG, 'cats before sorting=>${widget._dropDownCategories}');
    widget._dropDownCategories.sort();
    widget._dropDownCategories.insert(0, getLocalizedCategory(ANY_CATEGORY, context));
    widget._dropDownLanguages.sort();
    widget._dropDownLanguages.insert(0, getLocalizedLanguage(ANY_LANGUAGE, context));
    widget._filterCategory = getLocalizedCategory(widget._filterCategory, context);
    widget._filterLanguage = getLocalizedLanguage(widget._filterLanguage, context);
    setState(() => widget.hasFilter = (widget._dropDownCategories.length > 1 || widget._dropDownLanguages.length > 1));
    widget._linkOrList = list;
    return Future.value(list);
  }

  Future<List<Channel>> getFilteredChannels(Future<List<Channel>> f, String q) => f.then((list) => list.where((element) {
        element.query = widget._query ?? '';
        return ((q.isEmpty) ? true : element.title.toLowerCase().contains(q.toLowerCase())) &&
            (widget._filterLanguage != getLocalizedLanguage(ANY_LANGUAGE, context)
                ? element.languages.contains(widget._filterLanguage)
                : true) &&
            (widget._filterCategory != getLocalizedCategory(ANY_CATEGORY, context)
                ? element.categories.contains(widget._filterCategory)
                : true);
      }).toList());

  void dialog(ctx, submit, clear) => showDialog(
      context: ctx,
      builder: (_) => ZtvDialog(
          submit, clear, widget._filterLanguage, widget._filterCategory, widget._dropDownLanguages, widget._dropDownCategories));

  setChannelProperties(String s, Channel channel) {
    s = s.replaceAll('#EXTINF:-1 ', '');
    var item = '';
    var quoteCount = 0;
    for (final c in s.characters) {
      if (quoteCount == 2) {
        quoteCount = 0;
        continue;
      }
      if (c == '"')
        quoteCount++;
      else
        item += c;
      if (quoteCount == 2) {
        processItem(item, channel);
        item = '';
      }
    }
  }

  void processItem(String item, Channel channel) {
    String str;
    if (item.startsWith('tvg-language') && (str = item.split('=').last).isNotEmpty) {
      channel.languages.addAll(str.split(';').map((e) => getLocalizedLanguage(e, context)));
      if (channel.languages.contains(CASTILIAN)) {
        channel.languages.remove(CASTILIAN);
        channel.languages.add(getLocalizedLanguage(SPANISH, context));
      } else if (channel.languages.contains(FARSI)) {
        channel.languages.remove(FARSI);
        channel.languages.add(getLocalizedLanguage(PERSIAN, context));
      } else if (channel.languages.contains('Gernman')) {
        channel.languages.remove('Gernman');
        channel.languages.add(getLocalizedLanguage(GERMAN, context));
      } else if (channel.languages.contains('Japan')) {
        channel.languages.remove("Japan");
        channel.languages.add(getLocalizedLanguage(JAPANESE, context));
      } else if (channel.languages.contains('CA')) {
        channel.languages.remove('CA');
        channel.languages.add(getLocalizedLanguage(ENGLISH, context));
      } else if (channel.languages.any((l) => l.startsWith('Mandarin'))) {
        channel.languages.removeWhere((l) => l.startsWith('Mandarin'));
        channel.languages.add(getLocalizedLanguage(CHINESE, context));
      } else if (channel.languages.contains('Min')) {
        channel.languages.remove('Min');
        channel.languages.add(getLocalizedLanguage(CHINESE, context));
      } else if (channel.languages.contains('Modern')) {
        channel.languages.remove('Modern');
        channel.languages.add(getLocalizedLanguage(GREEK, context));
      } else if (channel.languages.contains('News')) {
        channel.languages.remove('News');
        channel.languages.add(getLocalizedLanguage(ENGLISH, context));
      } else if (channel.languages.contains('Panjabi')) {
        channel.languages.remove('Panjabi');
        channel.languages.add(getLocalizedLanguage(PUNJABI, context));
      } else if (channel.languages.contains('Western')) {
        channel.languages.remove('Western');
        channel.languages.add(getLocalizedLanguage(DUTCH, context));
      } else if (channel.languages.any((l) => l.startsWith('Yue'))) {
        channel.languages.removeWhere((l) => l.startsWith('Yue'));
        channel.languages.add(getLocalizedLanguage(CHINESE, context));
      } else if (channel.languages.contains('Central')) {
        channel.languages.remove('Central');
      } else if (channel.languages.contains('Dhivehi')) {
        channel.languages.remove('Dhivehi');
        channel.languages.add(getLocalizedLanguage(MALDIVIAN, context));
      } else if (channel.languages.contains('Kirghiz')) {
        channel.languages.remove('Kirghiz');
        channel.languages.add(getLocalizedLanguage(KYRGYZ, context));
      } else if (channel.languages.contains('Letzeburgesch')) {
        channel.languages.remove('Letzeburgesch');
        channel.languages.add(getLocalizedLanguage(LUXEMBOURGISH, context));
      } else if (channel.languages.contains('Northern Kurdish') || channel.languages.contains('Central Kurdish')) {
        channel.languages.removeWhere((e) => e == 'Central Kurdish' || e == 'Northern Kurdish');
        channel.languages.add(getLocalizedLanguage(KURDISH, context));
      } else if (channel.languages.contains('Assyrian Neo-Aramaic')) {
        channel.languages.remove('Assyrian Neo-Aramaic');
        channel.languages.add(getLocalizedLanguage(ASSYRIAN, context));
      } else if (channel.languages.contains('Norwegian Bokmål')) {
        channel.languages.remove('Norwegian Bokmål');
        channel.languages.add(getLocalizedLanguage(NORWEGIAN, context));
      } else if (channel.languages.any((l) => l.startsWith('Oriya'))) {
        channel.languages.removeWhere((l) => l.startsWith('Oriya'));
        channel.languages.add(getLocalizedLanguage(ODIA, context));
      }
    } else if (item.startsWith('tvg-logo') && (str = item.split('=').last).isNotEmpty) {
      channel.logo = str;
    } else if (item.startsWith('group-title') && (str = item.split('=').last).isNotEmpty) {
      channel.categories
          .addAll(str.split(';').where((element) => element != UNDEFINED).map((e) => getLocalizedCategory(e, context)));
    }
  }
}

class SaveDialog extends StatelessWidget {
  static const TAG = 'SaveDialog';

  var link;

  SaveDialog(this.link);

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    var name = 'Playlist_${now.year}_${now.month}_${now.day}_${now.hour}_${now.minute}_${now.second}';
    return AlertDialog(
      title: Text(AppLocalizations.of(context)?.save_playlist ?? 'Save playlist'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: TextEditingController(text: name),
            onChanged: (v) => name = v,
          )
        ],
      ),
      actions: [
        TextButton(
            onPressed: () {
              if (name.isEmpty) return;
              savePlaylist(Playlist(name, link));
              Navigator.of(context).pop();
            },
            child: const Text('Save'))
      ],
    );
  }

  Future<void> savePlaylist(Playlist playlist) async {
    openDatabase(p.join(await getDatabasesPath(), DB_NAME), onCreate: (db, v) {
      return db.execute('CREATE TABLE playlist(name TEXT, link TEXT PRIMARY KEY)');
    }, version: 1)
        .then((db) => db.insert('playlist', playlist.toMap(), conflictAlgorithm: ConflictAlgorithm.replace));
  }
}

class ZtvDialog extends StatefulWidget {
  final submit;
  final clear;
  var language;
  var category;
  final List<String> dropDownLanguages;
  final dropDownCategories;

  ZtvDialog(this.submit, this.clear, this.language, this.category, this.dropDownLanguages, this.dropDownCategories);

  @override
  State<StatefulWidget> createState() => DialogState();
}

class DialogState extends State<ZtvDialog> {
  static const TAG = 'DialogState';

  @override
  Widget build(BuildContext context) {
    var languageSpinnerAndTitle =
        SpinnerAndTitle(widget.language, AppLocalizations.of(context)?.language ?? 'Language', widget.dropDownLanguages);
    var categorySpinnerAndTitle =
        SpinnerAndTitle(widget.category, AppLocalizations.of(context)?.category ?? 'Category', widget.dropDownCategories);
    return AlertDialog(
        title: Padding(child: Text(AppLocalizations.of(context)?.filter ?? 'Filter'), padding: EdgeInsets.only(bottom: 16)),
        contentPadding: const EdgeInsets.only(left: 4, right: 4),
        actions: [
          TextButton(
              onPressed: () => setState(() {
                    widget.language = getLocalizedLanguage(ANY_LANGUAGE, context);
                    widget.category = getLocalizedCategory(ANY_CATEGORY, context);
                    widget.clear();
                  }),
              child: Text(AppLocalizations.of(context)?.reset ?? 'Reset')),
          TextButton(
              onPressed: () {
                widget.submit(languageSpinnerAndTitle.dropdownValue, categorySpinnerAndTitle.dropdownValue);
                Navigator.of(context).pop();
              },
              child: Text('OK'))
        ],
        content: Row(
          children: [
            Padding(padding: EdgeInsets.only(right: 2), child: languageSpinnerAndTitle),
            Padding(padding: EdgeInsets.only(left: 2), child: categorySpinnerAndTitle)
          ],
        ));
  }
}

class SpinnerAndTitle extends StatefulWidget {
  static const TAG = 'SpinnerAndTitle';
  var dropdownValue;
  String title;
  final items;

  SpinnerAndTitle(this.dropdownValue, this.title, this.items) {
    log(TAG, 'drop down val=>$dropdownValue');
  }

  @override
  State<StatefulWidget> createState() => SpinnerAndTitleState();
}

class SpinnerAndTitleState extends State<SpinnerAndTitle> {
  static const TAG = 'SpinnerAndTitleState';

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.title),
        DropdownButton<String>(
          value: widget.dropdownValue,
          onChanged: (String? newValue) {
            log(TAG, "on changed new val=>$newValue");
            setState(() {
              widget.dropdownValue = newValue;
            });
          },
          items: widget.items.map<DropdownMenuItem<String>>((String value) {
            return DropdownMenuItem<String>(
              value: value,
              child: Text(value),
            );
          }).toList(),
        )
      ],
    );
  }
}
