//! Evaluation of the `rules` arrays in version JSON.

use crate::mojang::{Rule, RuleAction};
use crate::platform;

/// Launcher-provided facts that conditional arguments can test.
#[derive(Debug, Clone, Copy, Default)]
pub struct Features {
    pub custom_resolution: bool,
}

impl Features {
    fn get(self, name: &str) -> bool {
        match name {
            "has_custom_resolution" => self.custom_resolution,
            _ => false,
        }
    }
}

/// Mojang semantics: no rules means allowed; otherwise the last matching rule decides.
pub fn allows(rules: &[Rule], features: Features) -> bool {
    if rules.is_empty() {
        return true;
    }
    let mut allowed = false;
    for rule in rules {
        if matches(rule, features) {
            allowed = rule.action == RuleAction::Allow;
        }
    }
    allowed
}

fn matches(rule: &Rule, features: Features) -> bool {
    if let Some(os) = &rule.os {
        if os
            .name
            .as_deref()
            .is_some_and(|name| name != platform::OS_NAME)
        {
            return false;
        }
        if os
            .arch
            .as_deref()
            .is_some_and(|arch| arch != platform::ARCH)
        {
            return false;
        }
        // Only Windows-specific arguments carry a version pattern; treating it as a
        // non-match merely omits those arguments elsewhere.
        if os.version.is_some() {
            return false;
        }
    }
    rule.features
        .iter()
        .all(|(name, expected)| features.get(name) == *expected)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::mojang::OsRule;

    fn rule(action: RuleAction, os: Option<&str>) -> Rule {
        Rule {
            action,
            os: os.map(|name| OsRule {
                name: Some(name.to_owned()),
                arch: None,
                version: None,
            }),
            features: HashMap::new(),
        }
    }

    use std::collections::HashMap;

    #[test]
    fn empty_rules_allow() {
        assert!(allows(&[], Features::default()));
    }

    #[test]
    fn last_matching_rule_wins() {
        let rules = [
            rule(RuleAction::Allow, None),
            rule(RuleAction::Disallow, Some(platform::OS_NAME)),
        ];
        assert!(!allows(&rules, Features::default()));
        let rules = [rule(RuleAction::Allow, Some("plan9"))];
        assert!(!allows(&rules, Features::default()));
    }

    #[test]
    fn features_must_match() {
        let mut rule = rule(RuleAction::Allow, None);
        rule.features
            .insert("has_custom_resolution".to_owned(), true);
        assert!(allows(
            std::slice::from_ref(&rule),
            Features {
                custom_resolution: true
            }
        ));
        assert!(!allows(std::slice::from_ref(&rule), Features::default()));
    }
}
