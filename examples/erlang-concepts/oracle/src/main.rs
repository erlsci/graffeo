//! Independent expected-results oracle for the erlang-concepts example.
//!
//! Generates `expected.json` — the reference against which the Erlang
//! example's output is checked. Built independently of the Erlang
//! implementation: CC writes the Erlang ingestion/queries, this oracle
//! computes the same facts in Rust (with petgraph), and CDC diffs the two.
//!
//! Regenerate with `make oracle-gen` (from `examples/erlang-concepts/`).

use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::LazyLock;

use anyhow::{Context, Result, bail};
use clap::Parser;
use petgraph::graph::{DiGraph, NodeIndex};
use petgraph::unionfind::UnionFind;
use regex::Regex;
use serde::Serialize;

const REL_KEYS: [&str; 4] = ["prerequisites", "extends", "related", "contrasts_with"];
const TOP_K: usize = 12;

static SLUG_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?m)^\s*slug:\s*(.+)$").unwrap_or_else(|_| unreachable!()));
static NEXT_KEY_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^[a-z_]+:").unwrap_or_else(|_| unreachable!()));
static ITEM_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^-\s*(.+)$").unwrap_or_else(|_| unreachable!()));

#[derive(Parser)]
#[command(about = "Generate expected.json for the erlang-concepts oracle")]
struct Cli {
    /// Path to the concept-cards directory
    #[arg(default_value = "../../workbench/ai-engineering/knowledge/erlang/concept-cards")]
    cards_dir: PathBuf,
}

// --- Front-matter parsing ---

fn front_matter(text: &str) -> &str {
    for part in text.split("---") {
        if part.contains("slug:") || part.contains("concept:") {
            return part;
        }
    }
    ""
}

fn slug_of(fm: &str, path: &Path) -> String {
    if let Some(caps) = SLUG_RE.captures(fm) {
        return caps[1].trim().trim_matches('"').to_string();
    }
    path.file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("unknown")
        .to_string()
}

fn list_field(fm: &str, key: &str) -> Vec<String> {
    let pattern = format!(r"(?m)^[ \t]*{key}:[ \t]*(.*)$");
    let re = Regex::new(&pattern).unwrap_or_else(|_| unreachable!());
    let Some(caps) = re.captures(fm) else {
        return vec![];
    };
    let inline = caps[1].trim();

    if inline.starts_with('[') {
        let body = inline.trim_start_matches('[').trim_end_matches(']').trim();
        if body.is_empty() {
            return vec![];
        }
        return body
            .split(',')
            .map(|x| x.trim().trim_matches('"').to_string())
            .filter(|x| !x.is_empty())
            .collect();
    }

    if !inline.is_empty() {
        return vec![inline.trim_matches('"').to_string()];
    }

    let m = caps.get(0).unwrap_or_else(|| unreachable!());
    let after = &fm[m.end()..];
    let mut out = vec![];
    for line in after.lines() {
        let stripped = line.trim();
        if NEXT_KEY_RE.is_match(stripped) {
            break;
        }
        if let Some(item) = ITEM_RE.captures(stripped) {
            out.push(item[1].trim().trim_matches('"').to_string());
        }
    }
    out
}

// --- Graph operations via petgraph ---

fn tarjan_cyclic_sccs(edges: &BTreeSet<(String, String)>) -> Vec<Vec<String>> {
    let mut node_ids: BTreeMap<&str, NodeIndex> = BTreeMap::new();
    let mut graph = DiGraph::<&str, ()>::new();

    for (x, y) in edges {
        for s in [x.as_str(), y.as_str()] {
            node_ids.entry(s).or_insert_with(|| graph.add_node(s));
        }
    }

    for (x, y) in edges {
        let a = node_ids[x.as_str()];
        let b = node_ids[y.as_str()];
        graph.add_edge(a, b, ());
    }

    let sccs = petgraph::algo::tarjan_scc(&graph);
    let mut cyclic = Vec::new();
    for scc in &sccs {
        if scc.len() > 1 {
            let mut members: Vec<String> = scc.iter().map(|&idx| graph[idx].to_string()).collect();
            members.sort();
            cyclic.push(members);
        } else if scc.len() == 1 {
            let idx = scc[0];
            if graph.contains_edge(idx, idx) {
                cyclic.push(vec![graph[idx].to_string()]);
            }
        }
    }
    cyclic.sort();
    cyclic
}

fn weak_component_sizes(edges: &[(String, String)]) -> Vec<u64> {
    let mut node_map: HashMap<&str, usize> = HashMap::new();
    for (x, y) in edges {
        let n = node_map.len();
        node_map.entry(x.as_str()).or_insert(n);
        let n = node_map.len();
        node_map.entry(y.as_str()).or_insert(n);
    }

    if node_map.is_empty() {
        return vec![];
    }

    let mut uf = UnionFind::new(node_map.len());
    for (x, y) in edges {
        uf.union(node_map[x.as_str()], node_map[y.as_str()]);
    }

    let mut groups: HashMap<usize, u64> = HashMap::new();
    for &idx in node_map.values() {
        *groups.entry(uf.find(idx)).or_default() += 1;
    }
    let mut sizes: Vec<u64> = groups.into_values().collect();
    sizes.sort_unstable_by(|a, b| b.cmp(a));
    sizes
}

// --- Output schema ---

#[derive(Serialize)]
struct Facts {
    abstract_edge_assertions_by_type: BTreeMap<String, u64>,
    all_relations_component_sizes_top: Vec<u64>,
    all_relations_giant_size: u64,
    all_relations_n_components: u64,
    five_book_slugs: Vec<String>,
    ghost_concepts: Vec<String>,
    n_abstract_ordered_pairs: u64,
    n_abstract_vertices: u64,
    n_multi_asserted_triples: u64,
    n_multi_book_slugs: u64,
    n_multi_typed_pairs: u64,
    n_prereq_cycles: u64,
    n_source_vertices: u64,
    prereq_cyclic_strong_components: Vec<Vec<String>>,
    prereq_edges: u64,
    prereq_nodes: u64,
    related_component_sizes_top: Vec<u64>,
    related_giant_size: u64,
    related_n_components: u64,
    sources: BTreeMap<String, u64>,
    top_k_by_total_degree: Vec<(String, u64)>,
}

// --- Main computation ---

fn compute(cards_dir: &Path) -> Result<Facts> {
    parser_selftest(cards_dir);

    let pattern = cards_dir.join("**/*.md");
    let pattern_str = pattern.to_str().context("cards_dir is not valid UTF-8")?;
    let mut files: Vec<PathBuf> = glob::glob(pattern_str)
        .context("glob pattern failed")?
        .filter_map(std::result::Result::ok)
        .collect();
    files.sort();

    if files.is_empty() {
        bail!(
            "no cards found under {} — run `make fetch-cards` first",
            cards_dir.display()
        );
    }

    let mut slug_sources: HashMap<String, BTreeSet<String>> = HashMap::new();
    let mut pair_types: HashMap<(String, String), BTreeSet<String>> = HashMap::new();
    let mut triple_books: HashMap<(String, String, String), u64> = HashMap::new();
    let mut typed_edges: HashMap<String, BTreeSet<(String, String)>> = HashMap::new();
    let mut source_counts: BTreeMap<String, u64> = BTreeMap::new();

    for f in &files {
        let rel = f.strip_prefix(cards_dir).unwrap_or(f);
        let source = rel
            .components()
            .next()
            .and_then(|c| c.as_os_str().to_str())
            .unwrap_or("unknown")
            .to_string();

        *source_counts.entry(source.clone()).or_default() += 1;

        let text =
            std::fs::read_to_string(f).with_context(|| format!("reading {}", f.display()))?;
        let fm = front_matter(&text);
        let x = slug_of(fm, f);
        slug_sources
            .entry(x.clone())
            .or_default()
            .insert(source.clone());

        for k in &REL_KEYS {
            for y in list_field(fm, k) {
                pair_types
                    .entry((x.clone(), y.clone()))
                    .or_default()
                    .insert((*k).to_string());
                *triple_books
                    .entry((x.clone(), y.clone(), (*k).to_string()))
                    .or_default() += 1;
                typed_edges
                    .entry((*k).to_string())
                    .or_default()
                    .insert((x.clone(), y.clone()));
            }
        }
    }

    let all_slugs: HashSet<&str> = slug_sources.keys().map(String::as_str).collect();

    // Degree centrality over all-types abstract graph
    let mut deg: HashMap<&str, u64> = HashMap::new();
    for (x, y) in pair_types.keys() {
        *deg.entry(x.as_str()).or_default() += 1;
        *deg.entry(y.as_str()).or_default() += 1;
    }
    let mut deg_vec: Vec<(&str, u64)> = deg.into_iter().collect();
    deg_vec.sort_by(|a, b| b.1.cmp(&a.1).then_with(|| a.0.cmp(b.0)));
    let top_k: Vec<(String, u64)> = deg_vec
        .into_iter()
        .take(TOP_K)
        .map(|(s, d)| (s.to_string(), d))
        .collect();

    // Prerequisites projection: cyclic SCCs
    let prereq_edges = typed_edges
        .get("prerequisites")
        .cloned()
        .unwrap_or_default();
    let mut prereq_nodes: BTreeSet<String> = BTreeSet::new();
    for (x, y) in &prereq_edges {
        prereq_nodes.insert(x.clone());
        prereq_nodes.insert(y.clone());
    }
    let cyclic_sccs = tarjan_cyclic_sccs(&prereq_edges);

    // Connectivity — two lenses
    let related_edges: Vec<(String, String)> = typed_edges
        .get("related")
        .map(|s| {
            let mut v: Vec<_> = s.iter().cloned().collect();
            v.sort();
            v
        })
        .unwrap_or_default();
    let related_sizes = weak_component_sizes(&related_edges);

    let mut all_rel_set: BTreeSet<(String, String)> = BTreeSet::new();
    for k in &REL_KEYS {
        if let Some(edges) = typed_edges.get(*k) {
            all_rel_set.extend(edges.iter().cloned());
        }
    }
    let all_rel_edges: Vec<(String, String)> = all_rel_set.into_iter().collect();
    let all_rel_sizes = weak_component_sizes(&all_rel_edges);

    // Coverage
    let multi_book: Vec<String> = slug_sources
        .iter()
        .filter(|(_, ss)| ss.len() > 1)
        .map(|(s, _)| s.clone())
        .collect();
    let mut five_book: Vec<String> = slug_sources
        .iter()
        .filter(|(_, ss)| ss.len() >= 5)
        .map(|(s, _)| s.clone())
        .collect();
    five_book.sort();

    // Ghosts
    let mut referenced: HashSet<&str> = HashSet::new();
    for (x, y) in pair_types.keys() {
        referenced.insert(x.as_str());
        referenced.insert(y.as_str());
    }
    let mut ghosts: Vec<String> = referenced
        .difference(&all_slugs)
        .map(|s| (*s).to_string())
        .collect();
    ghosts.sort();

    // Multi-typed / multi-asserted
    let multi_typed: Vec<String> = {
        let mut v: Vec<String> = pair_types
            .iter()
            .filter(|(_, ts)| ts.len() > 1)
            .map(|((x, y), _)| format!("{x} -> {y}"))
            .collect();
        v.sort();
        v
    };
    let multi_asserted: Vec<String> = {
        let mut v: Vec<String> = triple_books
            .iter()
            .filter(|(_, c)| **c > 1)
            .map(|((x, y, k), _)| format!("{x} -[{k}]-> {y}"))
            .collect();
        v.sort();
        v
    };

    let edge_type_counts: BTreeMap<String, u64> = REL_KEYS
        .iter()
        .map(|k| {
            (
                (*k).to_string(),
                typed_edges.get(*k).map_or(0, |s| s.len() as u64),
            )
        })
        .collect();

    #[allow(clippy::cast_possible_truncation)]
    let facts = Facts {
        sources: source_counts,
        n_source_vertices: files.len() as u64,
        n_abstract_vertices: all_slugs.len() as u64,
        n_multi_book_slugs: multi_book.len() as u64,
        five_book_slugs: five_book,
        abstract_edge_assertions_by_type: edge_type_counts,
        n_abstract_ordered_pairs: pair_types.len() as u64,
        n_multi_typed_pairs: multi_typed.len() as u64,
        n_multi_asserted_triples: multi_asserted.len() as u64,
        prereq_nodes: prereq_nodes.len() as u64,
        prereq_edges: prereq_edges.len() as u64,
        prereq_cyclic_strong_components: cyclic_sccs.clone(),
        n_prereq_cycles: cyclic_sccs.len() as u64,
        related_n_components: related_sizes.len() as u64,
        related_component_sizes_top: related_sizes.iter().take(8).copied().collect(),
        related_giant_size: related_sizes.first().copied().unwrap_or(0),
        all_relations_n_components: all_rel_sizes.len() as u64,
        all_relations_component_sizes_top: all_rel_sizes.iter().take(8).copied().collect(),
        all_relations_giant_size: all_rel_sizes.first().copied().unwrap_or(0),
        top_k_by_total_degree: top_k,
        ghost_concepts: ghosts,
    };

    Ok(facts)
}

fn parser_selftest(cards_dir: &Path) {
    let p = cards_dir.join("design-scale-erlang-otp/alarm-handler.md");
    let Ok(text) = std::fs::read_to_string(&p) else {
        return;
    };
    let fm = front_matter(&text);
    let checks = [
        ("prerequisites", vec!["event-manager", "event-handler"]),
        ("extends", vec!["event-handler"]),
        (
            "related",
            vec!["notifying-events", "swapping-event-handlers"],
        ),
        ("contrasts_with", vec![]),
    ];
    for (key, want) in &checks {
        let got = list_field(fm, key);
        let want_str: Vec<String> = want.iter().map(|s| (*s).to_string()).collect();
        assert_eq!(
            got, want_str,
            "parser self-test FAILED for alarm-handler {key}"
        );
    }
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    let facts = compute(&cli.cards_dir)?;
    let json = serde_json::to_string_pretty(&facts)?;
    println!("{json}");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_front_matter_extraction() {
        let text = "---\nslug: test\nconcept: Test\n---\n# Body";
        let fm = front_matter(text);
        assert!(fm.contains("slug: test"));
    }

    #[test]
    fn test_list_field_block() {
        let fm = "prerequisites:\n  - alpha\n  - beta\nextends: []\n";
        let got = list_field(fm, "prerequisites");
        assert_eq!(got, vec!["alpha", "beta"]);
    }

    #[test]
    fn test_list_field_inline_empty() {
        let fm = "contrasts_with: []\n";
        let got = list_field(fm, "contrasts_with");
        assert!(got.is_empty());
    }

    #[test]
    fn test_list_field_missing() {
        let fm = "slug: test\n";
        let got = list_field(fm, "extends");
        assert!(got.is_empty());
    }

    #[test]
    fn test_slug_of_from_frontmatter() {
        let fm = "slug: gen-server\nconcept: GenServer\n";
        assert_eq!(slug_of(fm, Path::new("gen-server.md")), "gen-server");
    }

    #[test]
    fn test_slug_of_fallback() {
        assert_eq!(slug_of("", Path::new("some-card.md")), "some-card");
    }

    #[test]
    fn test_alarm_handler_fixture() {
        let cards_dir =
            PathBuf::from("../../workbench/ai-engineering/knowledge/erlang/concept-cards");
        if cards_dir.is_dir() {
            parser_selftest(&cards_dir);
        }
    }
}
