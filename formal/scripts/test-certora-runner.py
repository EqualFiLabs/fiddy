#!/usr/bin/env python3
"""Exercise failure detection without invoking any prover or consuming saved results."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

module = importlib.util.spec_from_file_location("runner", Path(__file__).with_name("run-certora.py"))
runner = importlib.util.module_from_spec(module)
module.loader.exec_module(runner)


class EvidenceValidation(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.result = Path(self.directory.name) / "result.json"
        self.log = Path(self.directory.name) / "proof.log"
        self.suite = {"obligations": [{"context": ["accounting"], "methods": ["claim()", "settle()"]}],
                      "sanity": {"rule_not_vacuous": ["accounting-rule_not_vacuous"]}}
        self.result.write_text(json.dumps({"rules": {"accounting": {"SUCCESS": ["claim()", "settle()"]}}}))
        self.log.write_text("Starting to run on rule accounting-rule_not_vacuous\n"
                            "Violated: accounting-rule_not_vacuous\n")

    def check(self, code=0):
        runner.validate(self.suite, self.result, self.log, code)

    def test_complete_obligations(self):
        self.check()

    def test_nonzero_exit(self):
        with self.assertRaises(ValueError):
            self.check(1)

    def test_missing_method(self):
        self.result.write_text('{"rules":{"accounting":{"SUCCESS":["claim()"]}}}')
        with self.assertRaises(ValueError):
            self.check()

    def test_duplicate_method(self):
        self.result.write_text('{"rules":{"accounting":{"SUCCESS":["claim()","claim()"]}}}')
        with self.assertRaises(ValueError):
            self.check()

    def test_duplicate_rule_key(self):
        self.result.write_text('{"rules":{"accounting":"SUCCESS","accounting":"SUCCESS"}}')
        with self.assertRaises(ValueError):
            self.check()

    def test_unproved_statuses(self):
        for state in ["FAIL", "UNKNOWN", "TIMEOUT", "ERROR", "SKIPPED"]:
            with self.subTest(state=state):
                self.result.write_text(json.dumps({"rules": {"accounting": {state: ["claim()", "settle()"]}}}))
                with self.assertRaises(ValueError):
                    self.check()

    def test_missing_sanity(self):
        self.log.write_text("")
        with self.assertRaises(ValueError):
            self.check()

    def test_vacuous_or_contradictory_sanity(self):
        self.log.write_text(self.log.read_text() + "Verified: accounting-rule_not_vacuous\n")
        with self.assertRaises(ValueError):
            self.check()

    def test_duplicate_sanity(self):
        self.log.write_text(self.log.read_text() + "Violated: accounting-rule_not_vacuous\n")
        with self.assertRaises(ValueError):
            self.check()

    def test_empty_inventory(self):
        self.result.write_text('{"rules":{}}')
        with self.assertRaises(ValueError):
            self.check()


if __name__ == "__main__":
    unittest.main()
