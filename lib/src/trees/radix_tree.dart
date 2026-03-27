// Copyright 2024 Kingdom Seed. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:searchlight/src/text/fuzzy.dart';

/// Result of a radix tree find operation.
///
/// Maps words to the list of internal document IDs associated with each word.
typedef FindResult = Map<String, List<int>>;

/// A node in a compressed radix tree (Patricia trie).
///
/// Mirrors Orama's `RadixNode` from `trees/radix.ts`.
class RadixNode {
  /// Creates a [RadixNode].
  RadixNode(this.key, this.subword, {required this.isEnd});

  /// Deserializes a [RadixNode] from a JSON-compatible map.
  factory RadixNode.fromJson(Map<String, Object?> json) {
    final node = RadixNode(
      json['k']! as String,
      json['s']! as String,
      isEnd: json['e']! as bool,
    )..word = json['w']! as String;
    final dList = json['d']! as List<Object?>;
    for (final id in dList) {
      node.documentIds.add(id! as int);
    }
    final cList = json['c']! as List<Object?>;
    for (final entry in cList) {
      final pair = entry! as List<Object?>;
      final k = pair[0]! as String;
      final childJson = pair[1]! as Map<String, Object?>;
      node.children[k] = RadixNode.fromJson(childJson);
    }
    return node;
  }

  /// First character of the subword (edge key).
  String key;

  /// The edge label (subword) from the parent to this node.
  String subword;

  /// Children keyed by the first character of their subword.
  final Map<String, RadixNode> children = {};

  /// Document IDs stored at this node.
  final Set<int> documentIds = {};

  /// Whether this node marks the end of a complete word.
  bool isEnd;

  /// The full word accumulated from root to this node.
  String word = '';

  /// Updates [word] by concatenating the parent's word with this node's
  /// [subword].
  void updateParent(RadixNode parent) {
    word = parent.word + subword;
  }

  /// Adds a document ID to this node.
  void addDocument(int docId) {
    documentIds.add(docId);
  }

  /// Removes a document ID from this node.
  bool removeDocument(int docId) {
    return documentIds.remove(docId);
  }

  /// DFS collecting all end-of-word nodes in the subtree rooted at this node.
  ///
  /// If [exact] is true, only collects the node whose [word] equals [term].
  /// If [tolerance] is provided, filters by Levenshtein distance.
  FindResult findAllWords(
    FindResult output,
    String term, {
    bool exact = false,
    int? tolerance,
  }) {
    final stack = <RadixNode>[this];
    while (stack.isNotEmpty) {
      final node = stack.removeLast();

      if (node.isEnd) {
        final w = node.word;
        final docIDs = node.documentIds;

        if (exact && w != term) {
          continue;
        }

        if (!output.containsKey(w)) {
          if (tolerance != null && tolerance > 0) {
            final difference = (term.length - w.length).abs();
            if (difference <= tolerance &&
                boundedLevenshtein(term, w, tolerance).isBounded) {
              output[w] = [];
            } else {
              continue;
            }
          } else {
            output[w] = [];
          }
        }

        if (output.containsKey(w) && docIDs.isNotEmpty) {
          final docs = output[w]!;
          for (final docId in docIDs) {
            if (!docs.contains(docId)) {
              docs.add(docId);
            }
          }
        }
      }

      node.children.values.forEach(stack.add);
    }
    return output;
  }

  /// Inserts a [word] with [docId] into the tree rooted at this node.
  ///
  /// Handles edge splitting when a common prefix diverges.
  void insert(String word, int docId) {
    var node = this;
    var i = 0;
    final wordLength = word.length;

    while (i < wordLength) {
      final currentCharacter = word[i];
      final childNode = node.children[currentCharacter];

      if (childNode != null) {
        final edgeLabel = childNode.subword;
        final edgeLabelLength = edgeLabel.length;
        var j = 0;

        // Find common prefix length between edgeLabel and remaining word.
        while (j < edgeLabelLength &&
            i + j < wordLength &&
            edgeLabel[j] == word[i + j]) {
          j++;
        }

        if (j == edgeLabelLength) {
          // Edge label fully matches; proceed to the child node.
          node = childNode;
          i += j;
          if (i == wordLength) {
            // The word is a prefix of an existing word.
            if (!childNode.isEnd) {
              childNode.isEnd = true;
            }
            childNode.addDocument(docId);
            return;
          }
          continue;
        }

        // Split the edgeLabel at the common prefix.
        final commonPrefix = edgeLabel.substring(0, j);
        final newEdgeLabel = edgeLabel.substring(j);
        final newWordLabel = word.substring(i + j);

        // Create an intermediate node for the common prefix.
        final inbetweenNode =
            RadixNode(commonPrefix[0], commonPrefix, isEnd: false)
              ..updateParent(node);
        node.children[commonPrefix[0]] = inbetweenNode;

        // Update the existing childNode.
        childNode
          ..subword = newEdgeLabel
          ..key = newEdgeLabel[0]
          ..updateParent(inbetweenNode);
        inbetweenNode.children[newEdgeLabel[0]] = childNode;

        if (newWordLabel.isNotEmpty) {
          // Create a new node for the remaining part of the word.
          final newNode = RadixNode(newWordLabel[0], newWordLabel, isEnd: true)
            ..addDocument(docId)
            ..updateParent(inbetweenNode);
          inbetweenNode.children[newWordLabel[0]] = newNode;
        } else {
          // The word ends at the inbetweenNode.
          inbetweenNode
            ..isEnd = true
            ..addDocument(docId);
        }
        return;
      } else {
        // No matching child; create a new node.
        final newNode =
            RadixNode(currentCharacter, word.substring(i), isEnd: true)
              ..addDocument(docId)
              ..updateParent(node);
        node.children[currentCharacter] = newNode;
        return;
      }
    }

    // If we reach here, the word already exists in the tree.
    if (!node.isEnd) {
      node.isEnd = true;
    }
    node.addDocument(docId);
  }

  /// Fuzzy search using Levenshtein distance traversal.
  void _findLevenshtein(
    String term,
    int index,
    int tolerance,
    int originalTolerance,
    FindResult output,
  ) {
    final stack = <({RadixNode node, int index, int tolerance})>[
      (node: this, index: index, tolerance: tolerance),
    ];

    while (stack.isNotEmpty) {
      final (:node, :index, :tolerance) = stack.removeLast();

      if (node.word.startsWith(term)) {
        node.findAllWords(output, term);
        continue;
      }

      if (tolerance < 0) {
        continue;
      }

      if (node.isEnd) {
        final w = node.word;
        final docIDs = node.documentIds;
        if (w.isNotEmpty) {
          if (boundedLevenshtein(term, w, originalTolerance).isBounded) {
            output[w] = [];
          }
          if (output.containsKey(w) && docIDs.isNotEmpty) {
            final docs = output[w]!.toSet();
            docIDs.forEach(docs.add);
            output[w] = docs.toList();
          }
        }
      }

      if (index >= term.length) {
        continue;
      }

      final currentChar = term[index];

      // 1. If node has child matching term[index], push match.
      if (node.children.containsKey(currentChar)) {
        final childNode = node.children[currentChar]!;
        stack.add(
          (node: childNode, index: index + 1, tolerance: tolerance),
        );
      }

      // 2. Delete operation.
      stack.add(
        (node: node, index: index + 1, tolerance: tolerance - 1),
      );

      // 3. For each child: insert and substitute operations.
      for (final entry in node.children.entries) {
        final character = entry.key;
        final childNode = entry.value;

        // a) Insert operation.
        stack.add(
          (node: childNode, index: index, tolerance: tolerance - 1),
        );

        // b) Substitute operation.
        if (character != currentChar) {
          stack.add(
            (node: childNode, index: index + 1, tolerance: tolerance - 1),
          );
        }
      }
    }
  }

  /// Finds words matching the given [term].
  ///
  /// If [exact] is true, only returns an exact word match.
  /// If [tolerance] is provided, performs fuzzy matching via Levenshtein.
  FindResult find({
    required String term,
    bool exact = false,
    int? tolerance,
  }) {
    if (tolerance != null && tolerance > 0 && !exact) {
      final output = <String, List<int>>{};
      _findLevenshtein(term, 0, tolerance, tolerance, output);
      return output;
    } else {
      var node = this;
      var i = 0;
      final termLength = term.length;

      while (i < termLength) {
        final character = term[i];
        final childNode = node.children[character];

        if (childNode != null) {
          final edgeLabel = childNode.subword;
          final edgeLabelLength = edgeLabel.length;
          var j = 0;

          // Compare edge label with the term starting from position i.
          while (j < edgeLabelLength &&
              i + j < termLength &&
              edgeLabel[j] == term[i + j]) {
            j++;
          }

          if (j == edgeLabelLength) {
            // Full match of edge label; proceed to the child node.
            node = childNode;
            i += j;
          } else if (i + j == termLength) {
            // The term ends in the middle of the edge label.
            if (j == termLength - i) {
              // Term is a prefix of the edge label.
              if (exact) {
                return {};
              } else {
                final output = <String, List<int>>{};
                childNode.findAllWords(output, term, exact: exact);
                return output;
              }
            } else {
              return {};
            }
          } else {
            return {};
          }
        } else {
          return {};
        }
      }

      // Term fully matched; collect words starting from this node.
      final output = <String, List<int>>{};
      node.findAllWords(output, term, exact: exact);
      return output;
    }
  }

  /// Returns `true` if [term] exists as a prefix in the tree.
  bool contains(String term) {
    var node = this;
    var i = 0;
    final termLength = term.length;

    while (i < termLength) {
      final character = term[i];
      final childNode = node.children[character];

      if (childNode != null) {
        final edgeLabel = childNode.subword;
        final edgeLabelLength = edgeLabel.length;
        var j = 0;

        while (j < edgeLabelLength &&
            i + j < termLength &&
            edgeLabel[j] == term[i + j]) {
          j++;
        }

        if (j < edgeLabelLength) {
          return false;
        }

        i += edgeLabelLength;
        node = childNode;
      } else {
        return false;
      }
    }
    return true;
  }

  /// Removes the [term] from the tree and cleans up empty nodes.
  bool removeWord(String term) {
    if (term.isEmpty) {
      return false;
    }

    var node = this;
    final termLength = term.length;
    final stack = <({RadixNode parent, String character})>[];

    for (var i = 0; i < termLength;) {
      final character = term[i];
      if (node.children.containsKey(character)) {
        final childNode = node.children[character]!;
        stack.add((parent: node, character: character));
        i += childNode.subword.length;
        node = childNode;
      } else {
        return false;
      }
    }

    // Remove documents from the node.
    node.documentIds.clear();
    node.isEnd = false;

    // Clean up any nodes that no longer lead to a word.
    while (stack.isNotEmpty &&
        node.children.isEmpty &&
        !node.isEnd &&
        node.documentIds.isEmpty) {
      final (:parent, :character) = stack.removeLast();
      parent.children.remove(character);
      node = parent;
    }

    return true;
  }

  /// Removes a single [docId] from the node matching [term].
  ///
  /// If [exact] is true, only removes from the node with exact word match.
  bool removeDocumentByWord(String term, int docId, {bool exact = true}) {
    if (term.isEmpty) {
      return true;
    }

    var node = this;
    final termLength = term.length;

    for (var i = 0; i < termLength;) {
      final character = term[i];
      if (node.children.containsKey(character)) {
        final childNode = node.children[character]!;
        i += childNode.subword.length;
        node = childNode;

        if (exact && node.word != term) {
          // Do nothing if the exact condition is not met.
        } else {
          node.removeDocument(docId);
        }
      } else {
        return false;
      }
    }
    return true;
  }

  /// Serializes this node to a JSON-compatible map.
  Map<String, Object?> toJson() {
    return {
      'w': word,
      's': subword,
      'e': isEnd,
      'k': key,
      'd': documentIds.toList(),
      'c': [
        for (final entry in children.entries) [entry.key, entry.value.toJson()],
      ],
    };
  }
}

/// A compressed radix tree (Patricia trie) for full-text search.
///
/// Mirrors Orama's `RadixTree` from `trees/radix.ts`.
/// The tree is a root [RadixNode] with empty key, subword, and non-end state.
class RadixTree extends RadixNode {
  /// Creates an empty [RadixTree].
  RadixTree() : super('', '', isEnd: false);

  /// Deserializes a [RadixTree] from a JSON-compatible map.
  factory RadixTree.fromJson(Map<String, Object?> json) {
    final tree = RadixTree()
      ..word = json['w']! as String
      ..subword = json['s']! as String
      ..isEnd = json['e']! as bool
      ..key = json['k']! as String;
    final dList = json['d']! as List<Object?>;
    for (final id in dList) {
      tree.documentIds.add(id! as int);
    }
    final cList = json['c']! as List<Object?>;
    for (final entry in cList) {
      final pair = entry! as List<Object?>;
      final k = pair[0]! as String;
      final childJson = pair[1]! as Map<String, Object?>;
      tree.children[k] = RadixNode.fromJson(childJson);
    }
    return tree;
  }
}
