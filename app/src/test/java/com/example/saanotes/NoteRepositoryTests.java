package com.example.saanotes;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

@SpringBootTest
class NoteRepositoryTests {

    @Autowired
    NoteRepository repository;

    @Test
    void 저장한_노트를_분류로_조회한다() {
        repository.save(new Note("VPC 서브넷", "VPC", "퍼블릭과 프라이빗을 나눈다"));
        repository.save(new Note("IAM 정책", "IAM", "명시적 거부가 항상 우선한다"));

        assertThat(repository.findByCategoryOrderByIdDesc("IAM"))
                .extracting(Note::getTitle)
                .containsExactly("IAM 정책");
    }
}
