// Copyright 2022 Saferwall. All rights reserved.
// Use of this source code is governed by Apache v2 license
// license that can be found in the LICENSE file.

package kaspersky

import (
	"testing"

	multiav "github.com/saferwall/saferwall/internal/multiav"
)

type filePathTest struct {
	filepath string
	want     multiav.Result
}

var filepathScanTest = []filePathTest{
	{"../../test/testdata/765c3a580f885f5e4e4f98a709e9f0ce",
		multiav.Result{
			Infected: true, Output: "Trojan-Downloader.Win32.CodecPack.amyc"},
	},
}

func TestScanFile(t *testing.T) {
	s := Scanner{}
	for _, tt := range filepathScanTest {
		t.Run(tt.filepath, func(t *testing.T) {
			got, err := s.ScanFile(tt.filepath)
			if err != nil {
				t.Fatalf("TestScanFile(%s) failed, err: %s",
					tt.filepath, err)
			}
			if got != tt.want {
				t.Errorf("TestScanFile(%s) got %v, want %v",
					tt.filepath, got, tt.want)
			}
		})
	}
}
