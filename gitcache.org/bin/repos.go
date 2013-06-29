package main

import (
  "fmt"
  "os/exec"
  "os"
  "sort"
  "strings"
  "strconv"
  "net/http"
  "path/filepath"
  "time"
  "encoding/json"
  "html"
)

type commit struct {
  Repo string
  Secs string
  Sha1 string
  Author string
  Date string
  Comment string
}

type sortedRepos struct {
  r *map[string]commit
  s []commit
}

var repos map[string]commit
var sorted_repos []commit
var root_dir = "/cache/repos/pub"
var git_bin = "/usr/local/bin/git"

func (sr *sortedRepos) Len() int {
  return len(*sr.r)
}
 
func (sr *sortedRepos) Less(i, j int) bool {
  r := *sr.r
  ir := sr.s[i].Repo
  jr := sr.s[j].Repo

  is, _ := strconv.Atoi(r[ir].Secs)
  js, _ := strconv.Atoi(r[jr].Secs)

  return is > js
}
 
func (sr *sortedRepos) Swap(i, j int) {
  sr.s[i], sr.s[j] = sr.s[j], sr.s[i]
}

func updateRepoInfo(repo string) {
  cmd := exec.Command(git_bin, "log", "-1", "--pretty=format:%ct%n%h%n%an%n%cr%n%s")
  cmd.Dir = repo

  out, err := cmd.Output()
  if err != nil {
    fmt.Println("err: ", err)
    return
  }

  repo = strings.Replace(repo, root_dir + "/", "", 1)
  fields := strings.Split(string(out), "\n")
  eComment := html.EscapeString(fields[4])
  c := commit{Repo: repo, Secs: fields[0], Sha1: fields[1], Author: fields[2], Date: fields[3], Comment: eComment}
  repos[repo] = c
}

func sortRepos(sr *sortedRepos) {
  sort.Sort(sr)
  sorted_repos = sr.s
}

func dirNames(pathname string) []string {
  f, err := os.Open(pathname)
  if err != nil {
    fmt.Println("error reading dir: ", err)
    return []string{}
  }
  defer f.Close()

  dirs, e := f.Readdirnames(-1)
  if e != nil {
    fmt.Println("err: ", e)
    return []string{}
  }

  return dirs
}

func recurseOrUpdate(pathname string) {
  for _, dir := range dirNames(pathname) {
    rpath := filepath.Join(pathname, dir)
    if strings.HasSuffix(dir, ".git") {
      updateRepoInfo(rpath)
    } else {
      recurseOrUpdate(rpath)
    }
  }
}

func updateRepos() {
  recurseOrUpdate(root_dir)
}

//func updateRepos() {
  // update repos map with commit info for each repo
//  sources := []string{"code.google.com", "github.com", "gcc.gnu.org"}
//
//  for _, source := range sources {
//    for _, dir_ := range dirNames(filepath.Join(root_dir, source)) {
//      for _, dir := range dirNames(filepath.Join(root_dir, source, dir_)) {
//        repo := filepath.Join(source, dir_, dir)
//        updateRepoInfo(repo)
//      }
//    }
//  }
//}

func repoManager() {
  repos = make(map[string]commit)
  sr := new(sortedRepos)
  sr.r = &repos
  sr.s = make([]commit, len(repos))

  // sort the repos
  for {
    updateRepos()
 
    if len(sr.s) < len(repos) {
      for i := len(sr.s); i < len(repos); i++ {
        sr.s = append(sr.s, commit{})
      }
    }

    i := 0
    for _, c := range repos {
      sr.s[i] = c
      i++
    }

    sortRepos(sr)

    time.Sleep(360 * time.Second)
  }
}

func repoHandler(w http.ResponseWriter, r *http.Request) {
  b, err := json.Marshal(sorted_repos[:50])
  if err != nil {
    fmt.Println("err: ", err)
    return
  }

  w.Header().Set("Content-Type", "application/json")
  fmt.Fprint(w, string(b))
}

func main() {
  go repoManager()

  http.HandleFunc("/repos.json", repoHandler)

  err := http.ListenAndServe(":8081", nil)
  if err != nil {
    fmt.Println("ListenAndServe: ", err)
  }
}

