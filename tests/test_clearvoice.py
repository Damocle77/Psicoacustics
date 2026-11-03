"""Regression checks for Clearvoice gain staging (stdlib + FFmpeg 8.x).

Run: python3 -m unittest discover -s tests -v
"""
import array
import json
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
ANALYZER = ROOT / 'audio_analyzer_volamp_psycho.sh'
PROCESSOR = ROOT / 'aegis_sonar_wide_aura_voice_volamp_psycho.sh'
ATMOS = ROOT / 'atmos_to_51_dynaudnorm_psicho.sh'


def run(*args, cwd=None):
    return subprocess.run(args, cwd=cwd, check=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE).stdout


def assignment(path, name):
    return re.search(rf'^{name}="([^"]*)"$', path.read_text(), re.M)[1]


def function(name):
    return re.search(rf'^{name}\(\) \{{\n.*?^\}}', ANALYZER.read_text(),
                     re.M | re.S)[0]


class GainPolicy(unittest.TestCase):
    def call(self, name, *args):
        names = ('VOLAMP_BASE', 'VOLAMP_MAX', 'LOUDNESS_TARGET')
        script = '\n'.join(f'{n}="{assignment(ANALYZER, n)}"' for n in names)
        script += '\n' + function(name) + '\n' + name + ' "$@"'
        return run('bash', '-eu', '-c', script, 'test', *args).decode().strip()

    def test_loudness_steps_and_boundaries(self):
        for loudness, expected in [('', '2.0'), ('N/A', '2.0'), ('-21', '2.0'),
                                   ('-22.79', '2.0'), ('-22.8', '2.5'),
                                   ('-23.99', '2.5'), ('-24', '3.0')]:
            with self.subTest(loudness=loudness):
                self.assertEqual(self.call('loudness_to_volamp', loudness), expected)

    def test_lra_cap_and_missing_measurement(self):
        for gain, lra, expected in [('3.0', '18', '2.0'), ('2.5', '25', '2.0'),
                                    ('3.0', '17.99', '3.0'), ('1.0', '20', '1.0'),
                                    ('2.5', 'N/A', '2.5')]:
            with self.subTest(gain=gain, lra=lra):
                self.assertEqual(self.call('cap_volamp_by_lra', gain, lra), expected)

    def test_gain_labels(self):
        for gain, label in [('2.0', 'standard / make-up DSP'),
                            ('2.5', 'molto basso'), ('3.0', 'estremamente basso')]:
            self.assertEqual(self.call('source_volume_status', gain), label)


class AudioPipeline(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        for tool in ('ffmpeg', 'ffprobe'):
            version = run(tool, '-version').decode().splitlines()[0]
            if not re.search(r'version 8\.', version):
                raise RuntimeError(f'FFmpeg/ffprobe 8.x required: {version}')
        cls.tmp = tempfile.TemporaryDirectory(prefix='clearvoice-')
        cls.work = Path(cls.tmp.name)
        cls.fixture = cls.work / 'surround.mkv'
        expr = '|'.join(f'{amp}*sin(2*PI*{freq}*t)' for amp, freq in
                        [(0.3, 440), (0.25, 554), (0.4, 700),
                         (0.1, 60), (0.2, 830), (0.2, 990)])
        run('ffmpeg', '-v', 'error', '-f', 'lavfi', '-i',
            f'aevalsrc={expr}:s=48000:d=20:c=5.1(side)',
            '-c:a', 'eac3', '-b:a', '768k', '-metadata:s:a:0',
            'language=ita', str(cls.fixture))

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def probe(self, path):
        data = json.loads(run('ffprobe', '-v', 'error', '-show_streams',
                              '-show_format', '-of', 'json', str(path)))
        self.assertAlmostEqual(float(data['format']['duration']), 20, delta=0.15)
        run('ffmpeg', '-v', 'error', '-xerror', '-i', str(path),
            '-map', '0:a:0', '-f', 'null', '-')
        return data['streams']

    def test_all_presets_with_both_codecs_and_default_gain(self):
        for codec, bitrate in [('eac3', '768k'), ('ac3', '640k')]:
            for preset in ('aegis', 'sonar', 'wide', 'aura', 'voiceita'):
                with self.subTest(codec=codec, preset=preset):
                    log = run('bash', str(PROCESSOR), codec, 'no', bitrate,
                              preset, str(self.fixture), cwd=self.work).decode()
                    self.assertIn('Final volamp:   +2.0 dB', log)
                    output = self.work / f'surround_{codec.upper()}_{preset.capitalize()}.mkv'
                    stream = self.probe(output)[0]
                    self.assertEqual(stream['codec_name'], codec)
                    self.assertEqual(stream['channels'], 6)
                    self.assertEqual(stream['channel_layout'], '5.1(side)')

    def test_explicit_gain_still_overrides_default(self):
        folder = self.work / 'override'
        folder.mkdir()
        fixture = folder / 'input.mkv'
        fixture.symlink_to(self.fixture)
        log = run('bash', str(PROCESSOR), 'eac3', 'no', '768k', 'sonar',
                  '3.5', str(fixture), cwd=folder).decode()
        self.assertIn('Final volamp:   +3.5 dB', log)
        self.probe(folder / 'input_EAC3_Sonar.mkv')

    def test_normalizer_preserves_original_stream_and_duration(self):
        run('bash', str(ATMOS), str(self.fixture), '768k', cwd=self.work)
        streams = self.probe(self.work / 'surround-0.mkv')
        self.assertEqual(len(streams), 2)
        self.assertEqual(streams[0]['channels'], 6)
        self.assertEqual(streams[0]['codec_name'], 'eac3')
        self.assertEqual(streams[0]['disposition']['default'], 1)
        self.assertEqual(streams[1]['disposition']['default'], 0)
        def audio_hash(path, selector):
            return run('ffmpeg', '-v', 'error', '-i', str(path), '-map', selector,
                       '-c', 'copy', '-f', 'hash', '-hash', 'sha256', '-')
        self.assertEqual(audio_hash(self.fixture, '0:a:0'),
                         audio_hash(self.work / 'surround-0.mkv', '0:a:1'))

    def test_stage_one_gain_ceiling_and_latency(self):
        graph = assignment(ATMOS, 'DYNAUDNORM')
        # Exercise the actual graph on low-level and over-range signals.
        for level, ceiling in [(0.01, 0.04), (2, 0.89)]:
            with self.subTest(level=level):
                pcm = run('ffmpeg', '-v', 'error', '-f', 'lavfi', '-i',
                          f'aevalsrc={level}:s=48000:d=20', '-af', graph,
                          '-c:a', 'pcm_f32le', '-f', 'f32le', '-')
                samples = array.array('f')
                samples.frombytes(pcm)
                self.assertEqual(len(samples), 20 * 48000)
                self.assertGreater(max(samples), 0)
                self.assertLessEqual(max(map(abs, samples)), ceiling + 1e-6)


if __name__ == '__main__':
    unittest.main()
