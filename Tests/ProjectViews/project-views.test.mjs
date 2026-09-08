import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import {createRequire} from 'node:module';
import {apply as host} from '../../Resources/ProjectViews/project-views-host.mjs';
let registration;
vm.runInNewContext(readFileSync(new URL('../../Resources/ProjectViews/project-views-client.js', import.meta.url), 'utf8'), {
  window: {__ModuleLoader__: {load: value => registration = value}}
});
const {selectedWorkspace, createNavigation} = registration.factory();
const workspaces = {baselinesReady: true, items: [
  {workspaceId: 'reading', path: '/same', sessionIds: ['one', 'two']},
  {workspaceId: 'coding', path: '/same', sessionIds: ['three']}
]};
assert.equal(selectedWorkspace({current: 'two', byId: {}}, workspaces).workspaceId, 'reading');
assert.equal(selectedWorkspace({current: 'three', byId: {}}, workspaces).workspaceId, 'coding');
assert.equal(selectedWorkspace({current: 'unassigned', byId: {unassigned: {cwd: '/same'}}}, workspaces), undefined);
assert.equal(selectedWorkspace({current: 'one', byId: {}}, {...workspaces, baselinesReady: false}), undefined);
assert.equal(selectedWorkspace({current: 'child', byId: {child: {origin: 'subagent', parentId: 'one'}}}, workspaces).workspaceId, 'reading');
assert.equal(selectedWorkspace({current: 'loop', byId: {loop: {origin: 'subagent', parentId: 'loop'}}}, workspaces), undefined);
const navigation = createNavigation();
navigation.select(workspaces.items[0]);
navigation.mode = 'folder'; navigation.path = 'articles';
const first = navigation.ticket();
assert.equal(navigation.select({...workspaces.items[0], title: 'Renamed'}), false);
assert.equal(navigation.path, 'articles'); assert.equal(navigation.mode, 'folder'); assert.equal(first(), true);
navigation.select(workspaces.items[1]);
assert.equal(first(), false); assert.equal(navigation.path, ''); assert.equal(navigation.mode, 'traditional');
const second = navigation.ticket(); navigation.invalidate(); assert.equal(second(), false);
let route, transform;
host({effect: fn => fn(), webServer: {register: value => {route = value; return () => {};}, tapIndex: value => {transform = value; return () => {};}}});
assert.equal(route.path, '/dsh-desktop/project-views.js');
const html = transform('<html><head></head><body></body></html>');
const inline = html.match(/<script>([\s\S]+)<\/script>/)[1];
const boot = {entries: []};
vm.runInNewContext(inline, {__DSH_BOOT__: boot, window: {}});
assert.equal(boot.entries.length, 0, 'ordinary browsers keep the original interface');
vm.runInNewContext(inline, {__DSH_BOOT__: boot, window: {webkit: {messageHandlers: {dshProjectFiles: {}}}}});
assert.equal(boot.entries.length, 1);
let served;
route.handler({}, {writeHead: status => assert.equal(status, 200), end: text => served = text});
assert.ok(served.includes('.dpv-header'));
new vm.Script(served);
const MarkdownIt = createRequire(import.meta.url)('../../Resources/ProjectViews/vendor/markdown-it.min.js');
const markdown = vm.runInNewContext(readFileSync(new URL('../../Resources/ProjectViews/markdown-document.js',import.meta.url),'utf8'));
const render = markdown.renderer(MarkdownIt);
const rendered = render('# 阅读标题\n\n**重点**\n\n| 名称 | 状态 |\n| --- | --- |\n| 文档 | 已完成 |\n\n```js\nalert("text only")\n```\n\n<script>alert(1)</script>\n\n[危险](javascript:alert(1))\n\n![图片](https://example.com/tracker.png)');
assert.ok(rendered.includes('<h1 id="dpv-md-阅读标题">'));assert.ok(rendered.includes('<table>'));assert.ok(rendered.includes('<strong>重点</strong>'));assert.ok(rendered.includes('<pre><code'));
assert.ok(!rendered.includes('<script>'));assert.ok(!rendered.includes('href="javascript:'));assert.ok(!rendered.includes('<img'));assert.ok(rendered.includes('data-md-image='));
assert.equal(markdown.localTarget('docs/article.md','../assets/a%20b.png'),'assets/a b.png');
for(const link of ['../../private.md','%2e%2e/%2e%2e/private.md','/private.md','file:///private.md','//remote/a','https://example.com/a','bad%zz'])assert.equal(markdown.localTarget('docs/article.md',link),null);
assert.equal(markdown.isMarkdown('资料.MD'),true);assert.equal(markdown.isMarkdown('image.png'),false);
console.log('Project views: workspace identity, stale requests, per-project navigation, native-only boot and bundled script passed.');
