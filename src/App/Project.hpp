#pragma once

// Generated by xmake from config/Project.hpp.in

#include <semver.hpp>

namespace App::Project
{
constexpr auto Name = "RedHotTools";
constexpr auto Author = "psiberx";

constexpr auto NameW = L"RedHotTools";
constexpr auto AuthorW = L"psiberx";

constexpr auto Version = semver::from_string_noexcept("0.4.7").value();
}
