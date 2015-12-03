# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import os.path
import sys

from kolla_mesos.common import file_utils
from kolla_mesos.tests import base


class FindBaseDirTest(base.BaseTestCase):

    def test_when_is_a_test(self):
        mod_dir = os.path.dirname(sys.modules[__name__].__file__)
        project_dir = os.path.abspath(os.path.join(mod_dir, '..', '..', '..'))
        tdir = file_utils.find_base_dir(project='kolla-mesos')
        self.assertEqual(project_dir, tdir)